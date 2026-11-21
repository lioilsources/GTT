package steps

import (
	"bufio"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"log/slog"
	"math"
	"os"
	"strconv"

	"citypack/internal/duck"
	"citypack/internal/geo"
)

// Widen clips building footprints by the widened road corridors (METROPOLE_PLAN 5.3 step 3).
// Ground-level roads only: tunnels pass under buildings and viaducts over them.
func Widen(e *Env) error {
	out := e.W("buildings_clipped.parquet")
	if e.fresh(out) {
		skip("widen", out)
		return nil
	}
	g, err := e.LoadGraph()
	if err != nil {
		return err
	}
	roadsCSV := e.W("road_buffers.csv")
	f, err := os.Create(roadsCSV)
	if err != nil {
		return err
	}
	w := csv.NewWriter(f)
	_ = w.Write([]string{"wkt", "hw"})
	for _, ed := range g.Edges {
		if ed.Tunnel || ed.LayerFrom != 0 || ed.LayerTo != 0 {
			continue
		}
		wkt := "LINESTRING("
		for i, p := range EdgePts(ed) {
			if i > 0 {
				wkt += ","
			}
			wkt += fmt.Sprintf("%.2f %.2f", p.X, p.Y)
		}
		wkt += ")"
		_ = w.Write([]string{wkt, strconv.FormatFloat(float64(ed.WidthM)/2, 'f', 2, 64)})
	}
	w.Flush()
	if err := f.Close(); err != nil {
		return err
	}
	area := e.projSQL("ST_GeomFromText(" + duck.Quote(e.C.City.AreaWKT()) + ")")
	sql := fmt.Sprintf(`
CREATE TABLE area AS SELECT %[1]s AS g;
CREATE TABLE roads AS SELECT ST_Buffer(ST_GeomFromText(wkt), hw::DOUBLE, 4) AS g FROM read_csv(%[2]s, header=true, quote='"');
CREATE TABLE src AS
  SELECT id, false AS part, NULL::VARCHAR AS parent, height, min_height, num_floors, coalesce(has_parts, false) AS has_parts,
         ST_MakeValid(%[3]s) AS g
  FROM read_parquet(%[4]s) WHERE NOT coalesce(is_underground, false)
  UNION ALL
  SELECT id, true, building_id, height, min_height, num_floors, false, ST_MakeValid(%[5]s)
  FROM read_parquet(%[6]s) WHERE NOT coalesce(is_underground, false);
DELETE FROM src WHERE NOT ST_Intersects(g, (SELECT g FROM area));
CREATE TABLE hit AS SELECT s.id, s.part, ST_Union_Agg(r.g) AS rg FROM src s JOIN roads r ON ST_Intersects(s.g, r.g) GROUP BY s.id, s.part;
COPY (
  SELECT s.id, s.part, s.parent, s.height, s.min_height, s.num_floors, s.has_parts,
         CASE WHEN h.rg IS NULL THEN s.g ELSE ST_Difference(s.g, h.rg) END AS g
  FROM src s LEFT JOIN hit h ON h.id = s.id AND h.part = s.part
) TO %[7]s (FORMAT parquet);
`, area, duck.Quote(roadsCSV), e.projSQL("geometry"), duck.Quote(e.Raw("building")),
		e.projSQL("geometry"), duck.Quote(e.Raw("building_part")), duck.Quote(out))
	_, err = duck.Exec("widen", sql)
	return err
}

// MassRow is one building mass handed from Buildings to Pack.
type MassRow struct {
	Rings    [][]geo.Pt
	HeightM  float64
	MinH     float64
	Landmark int // 1-based index into content landmarks, 0 none
	Part     bool
	SourceID string
}

// Buildings simplifies footprints, resolves heights and merges neighbours of the same
// height band into masses (METROPOLE_PLAN 5.3 step 4). Landmarks and stacked parts stay separate.
func Buildings(e *Env) error {
	out := e.W("buildings.jsonl")
	if e.fresh(out) {
		skip("buildings", out)
		return nil
	}
	lmCSV := e.W("landmark_points.csv")
	f, err := os.Create(lmCSV)
	if err != nil {
		return err
	}
	w := csv.NewWriter(f)
	_ = w.Write([]string{"idx", "x", "y", "h", "overture_id"})
	for i, l := range e.C.Landmarks {
		if l.Kind != "" {
			continue
		}
		p := e.Proj.Forward(l.Lon, l.Lat)
		_ = w.Write([]string{strconv.Itoa(i + 1), fmt.Sprintf("%.2f", p.X), fmt.Sprintf("%.2f", p.Y),
			fmt.Sprintf("%.1f", l.HeightM), l.OvertureID})
	}
	w.Flush()
	if err := f.Close(); err != nil {
		return err
	}
	def := e.C.City.DefaultHeightM
	bt := e.C.Tuning.Buildings
	sql := fmt.Sprintf(`
CREATE TABLE lm AS SELECT idx::INT AS idx, x::DOUBLE AS x, y::DOUBLE AS y, h::DOUBLE AS h, coalesce(overture_id, '') AS oid
  FROM read_csv(%[1]s, header=true, all_varchar=true);
CREATE TABLE c AS
  SELECT id, part, parent, has_parts,
         coalesce(height, num_floors * %[5]f, %[2]f) AS h, coalesce(min_height, 0) AS mh,
         ST_SimplifyPreserveTopology(g, %[6]f) AS g
  FROM read_parquet(%[3]s) WHERE NOT ST_IsEmpty(g) AND ST_Area(g) >= %[7]f;
-- Landmark ↔ building: explicit Overture id, else the nearest building within landmark_search_m
-- (containing buildings first, the largest of them).
CREATE TABLE lmb AS
  SELECT lm.idx, lm.h,
         arg_min(c.id, round(ST_Distance(c.g, ST_Point(lm.x, lm.y)), 0) * 1e9 - ST_Area(c.g)) AS id
  FROM lm JOIN c
    ON NOT c.part AND (c.id = lm.oid OR (lm.oid = '' AND ST_DWithin(c.g, ST_Point(lm.x, lm.y), %[8]f)))
  GROUP BY lm.idx, lm.h;
CREATE TABLE parents_with_parts AS SELECT DISTINCT parent AS id FROM c WHERE part;
-- Parts: scale a landmark's parts so its tallest part matches the curated height.
CREATE TABLE parts AS
  SELECT p.id, p.g, p.mh, p.h, coalesce(lmb.idx, 0) AS lm,
         CASE WHEN lmb.h > 0 THEN lmb.h / max(p.h) OVER (PARTITION BY p.parent) ELSE 1 END AS k
  FROM c p LEFT JOIN lmb ON lmb.id = p.parent WHERE p.part;
CREATE TABLE singles AS
  SELECT c.id, c.g, 0.0 AS mh, CASE WHEN lmb.h > 0 THEN lmb.h ELSE c.h END AS h, lmb.idx AS lm
  FROM c JOIN lmb ON lmb.id = c.id WHERE c.id NOT IN (SELECT id FROM parents_with_parts);
CREATE TABLE plain AS
  SELECT id, g, h,
         %[9]s AS band
  FROM c WHERE NOT part AND id NOT IN (SELECT id FROM parents_with_parts) AND id NOT IN (SELECT id FROM lmb);
CREATE TABLE clustered AS SELECT *, ST_ClusterDBSCAN(g, %[10]f, 1) OVER (PARTITION BY band) AS cid FROM plain;
CREATE TABLE masses AS
  SELECT 'mass-' || band || '-' || coalesce(cid, -row_number() OVER ()) AS id, ST_Union_Agg(g) AS g,
         sum(h * ST_Area(g)) / nullif(sum(ST_Area(g)), 0) AS h
  FROM clustered GROUP BY band, cid;
CREATE TABLE all_rows AS
  SELECT id, g, h, 0.0 AS mh, 0 AS lm, false AS part FROM masses
  UNION ALL SELECT id, g, h, mh, lm, false FROM singles
  UNION ALL SELECT id, g, h * k, mh * k, lm, true FROM parts;
COPY (
  SELECT id, coalesce(h, %[2]f) AS h, mh, lm, part, ST_AsGeoJSON(d.geom)::JSON AS geom
  FROM (SELECT id, h, mh, lm, part, unnest(ST_Dump(ST_MakeValid(g))) AS d FROM all_rows)
  WHERE ST_GeometryType(d.geom) = 'POLYGON' AND ST_Area(d.geom) >= %[11]f
) TO %[4]s (FORMAT json);
`, duck.Quote(lmCSV), def, duck.Quote(e.W("buildings_clipped.parquet")), duck.Quote(out+".tmp"),
		bt.FloorHeightM, bt.SimplifyM, bt.DegenerateM2, bt.LandmarkSearchM, bandSQL(bt.HeightBandsM), bt.MergeGapM, bt.MinAreaM2)
	if _, err := duck.Exec("buildings", sql); err != nil {
		return err
	}
	if err := os.Rename(out+".tmp", out); err != nil {
		return err
	}
	rows, err := e.LoadMasses()
	if err != nil {
		return err
	}
	matched := map[int]bool{}
	for _, r := range rows {
		if r.Landmark > 0 {
			matched[r.Landmark] = true
		}
	}
	for i, l := range e.C.Landmarks {
		if l.Kind == "" && !matched[i+1] {
			slog.Warn("landmark matched no building", "id", l.ID)
		}
	}
	slog.Info("buildings", "masses", len(rows), "landmarks_matched", len(matched))
	return nil
}

// bandSQL turns height band edges into a CASE expression: band i holds heights below edge i.
func bandSQL(edges []float64) string {
	s := "CASE"
	for i, e := range edges {
		s += fmt.Sprintf(" WHEN h < %f THEN %d", e, i)
	}
	return s + fmt.Sprintf(" ELSE %d END", len(edges))
}

// LoadMasses reads buildings.jsonl.
func (e *Env) LoadMasses() ([]MassRow, error) {
	f, err := os.Open(e.W("buildings.jsonl"))
	if err != nil {
		return nil, fmt.Errorf("buildings.jsonl missing, run buildings first: %w", err)
	}
	defer f.Close()
	var out []MassRow
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<26)
	for sc.Scan() {
		var r struct {
			ID   string  `json:"id"`
			H    float64 `json:"h"`
			MH   float64 `json:"mh"`
			LM   int     `json:"lm"`
			Part bool    `json:"part"`
			Geom struct {
				Coordinates [][][2]float64 `json:"coordinates"`
			} `json:"geom"`
		}
		if err := json.Unmarshal(sc.Bytes(), &r); err != nil {
			return nil, err
		}
		// Round heights to decimetres: merged heights are float sums in no fixed order.
		m := MassRow{HeightM: math.Round(r.H*10) / 10, MinH: math.Round(r.MH*10) / 10, Landmark: r.LM, Part: r.Part, SourceID: r.ID}
		for i, ring := range r.Geom.Coordinates {
			pts := make([]geo.Pt, len(ring))
			for j, c := range ring {
				pts[j] = geo.Pt{X: c[0], Y: c[1]}
			}
			pts = geo.OpenRing(pts)
			if len(pts) < 3 {
				continue
			}
			m.Rings = append(m.Rings, geo.Canonical(geo.Orient(pts, i == 0)))
		}
		if len(m.Rings) > 0 && len(m.Rings[0]) >= 3 {
			out = append(out, m)
		}
	}
	return out, sc.Err()
}
