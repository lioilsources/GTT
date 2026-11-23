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
	"strings"

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
	gap := e.C.Tuning.Flow.GapCloseM
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
-- FL0 (specs/flow.md): close gaps narrower than flow.gap_close_m between two or more ground masses (buffer
-- +gap/2, union, buffer −gap/2), never into a road corridor; each gap joins its biggest neighbour.
-- Inputs snap to a 1 cm grid so the overlays stay noded (GEOS TopologyException otherwise).
CREATE TABLE r0 AS SELECT row_number() OVER (ORDER BY id, part, mh, h) AS rid, id, ST_MakeValid(ST_ReducePrecision(g, 0.01)) AS g, h, mh, lm, part FROM all_rows;
CREATE TABLE roads AS SELECT ST_ReducePrecision(ST_Buffer(ST_GeomFromText(wkt), hw::DOUBLE, 4), 0.01) AS g FROM read_csv(%[12]s, header=true, quote='"');
CREATE TABLE gr AS SELECT rid, g, ST_ClusterDBSCAN(g, %[13]f, 2) OVER () AS cl FROM r0 WHERE mh < 0.5 AND NOT ST_IsEmpty(g);
CREATE TABLE cu AS SELECT cl, ST_Union_Agg(g) AS u FROM gr WHERE cl IS NOT NULL GROUP BY cl;
CREATE TABLE gaps0 AS
  SELECT cl, ST_Difference(ST_Buffer(ST_Buffer(u, %[14]f, 2, 'CAP_SQUARE', 'JOIN_MITRE', 5.0), -%[14]f, 2, 'CAP_SQUARE', 'JOIN_MITRE', 5.0), u) AS g FROM cu;
CREATE TABLE gaps1 AS SELECT row_number() OVER () AS gid, cl, d.geom AS g FROM (SELECT cl, unnest(ST_Dump(g)) AS d FROM gaps0)
  WHERE ST_GeometryType(d.geom) = 'POLYGON' AND ST_Area(d.geom) >= 1.0;
CREATE TABLE gap_roads AS SELECT ga.gid, ST_Union_Agg(r.g) AS rg FROM gaps1 ga JOIN roads r ON ST_Intersects(ga.g, r.g) GROUP BY ga.gid;
CREATE TABLE gaps2 AS SELECT ga.cl, CASE WHEN x.rg IS NULL THEN ga.g ELSE ST_Difference(ga.g, x.rg) END AS g FROM gaps1 ga LEFT JOIN gap_roads x USING (gid);
CREATE TABLE gaps AS SELECT row_number() OVER () AS gid, cl, d.geom AS g FROM (SELECT cl, unnest(ST_Dump(g)) AS d FROM gaps2)
  WHERE ST_GeometryType(d.geom) = 'POLYGON' AND ST_Area(d.geom) >= 1.0;
CREATE TABLE gap_owner AS
  SELECT ga.gid, arg_max(gr.rid, round(ST_Area(ST_Intersection(ST_Buffer(ga.g, 0.3), gr.g)), 2) * 1e7 - gr.rid) AS rid
  FROM gaps ga JOIN gr ON gr.cl = ga.cl AND ST_DWithin(ga.g, gr.g, 0.3) GROUP BY ga.gid
  HAVING count(DISTINCT gr.rid) >= 2;
CREATE TABLE gap_add AS SELECT o.rid, ST_Union_Agg(ga.g) AS g FROM gap_owner o JOIN gaps ga USING (gid) GROUP BY o.rid;
CREATE TABLE closed AS
  SELECT r0.id, CASE WHEN a.g IS NULL THEN r0.g ELSE ST_Union(r0.g, a.g) END AS g, r0.h, r0.mh, r0.lm, r0.part
  FROM r0 LEFT JOIN gap_add a USING (rid);
COPY (SELECT count(*) AS n FROM gap_owner) TO %[15]s (FORMAT csv, HEADER true);
COPY (
  SELECT id, coalesce(h, %[2]f) AS h, mh, lm, part, ST_AsGeoJSON(d.geom)::JSON AS geom
  FROM (SELECT id, h, mh, lm, part, unnest(ST_Dump(ST_MakeValid(g))) AS d FROM closed)
  WHERE ST_GeometryType(d.geom) = 'POLYGON' AND ST_Area(d.geom) >= %[11]f
) TO %[4]s (FORMAT json);
`, duck.Quote(lmCSV), def, duck.Quote(e.W("buildings_clipped.parquet")), duck.Quote(out+".tmp"),
		bt.FloorHeightM, bt.SimplifyM, bt.DegenerateM2, bt.LandmarkSearchM, bandSQL(bt.HeightBandsM), bt.MergeGapM, bt.MinAreaM2,
		duck.Quote(e.W("road_buffers.csv")), gap, gap/2, duck.Quote(e.W("gaps.csv")))
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
	closed := 0
	if b, err := os.ReadFile(e.W("gaps.csv")); err == nil {
		var n int
		if _, err := fmt.Sscanf(strings.TrimPrefix(string(b), "n\n"), "%d", &n); err == nil {
			closed = n
		}
	}
	slog.Info("buildings", "masses", len(rows), "landmarks_matched", len(matched), "closed_gaps", closed)
	return writeJSON(e.W("flow_gaps.json"), map[string]int{"closed_gaps": closed})
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
