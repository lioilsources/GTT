package steps

import (
	"bufio"
	"encoding/json"
	"fmt"
	"math"
	"os"

	"citypack/internal/duck"
	"citypack/internal/geo"
	"citypack/internal/pb"
)

// GroundRow is one ground polygon already clipped to a chunk cell.
type GroundRow struct {
	CX, CY int
	Kind   pb.GroundKind
	Rings  [][]geo.Pt
}

// Ground clips water, parks, plazas and rail yards to the area and the chunk grid
// (METROPOLE_PLAN 5.3 step 5). Rivers keep their real width.
func Ground(e *Env) error {
	out := e.W("ground.jsonl")
	if e.fresh(out) {
		skip("ground", out)
		return nil
	}
	cm := float64(e.C.Tuning.ChunkM)
	x0, y0, x1, y1 := e.chunkRange()
	area := e.projSQL("ST_GeomFromText(" + duck.Quote(e.C.City.AreaWKT()) + ")")
	proj := e.projSQL("geometry")
	sql := fmt.Sprintf(`
CREATE TABLE area AS SELECT %[1]s AS g;
CREATE TABLE src AS
  SELECT %[2]d AS kind, %[3]s AS g FROM read_parquet(%[4]s)
    WHERE class <> 'swimming_pool' AND ST_GeometryType(geometry) IN ('POLYGON', 'MULTIPOLYGON')
  UNION ALL
  SELECT CASE WHEN subtype = 'pedestrian' THEN %[5]d WHEN subtype = 'transportation' THEN %[6]d ELSE %[7]d END, %[3]s
    FROM read_parquet(%[8]s)
    WHERE (subtype IN ('park', 'recreation', 'pedestrian', 'transportation')
        OR class IN ('grass', 'garden', 'cemetery', 'village_green'))
      AND class NOT IN ('track', 'pitch_indoor')
      AND ST_GeometryType(geometry) IN ('POLYGON', 'MULTIPOLYGON')
  UNION ALL
  SELECT %[7]d, %[3]s FROM read_parquet(%[9]s)
    WHERE subtype IN ('forest', 'shrub', 'grass') AND ST_GeometryType(geometry) IN ('POLYGON', 'MULTIPOLYGON');
CREATE TABLE merged AS
  SELECT kind, ST_Intersection(ST_Union_Agg(ST_MakeValid(g)), (SELECT g FROM area)) AS g FROM src
  WHERE ST_Intersects(g, (SELECT g FROM area)) GROUP BY kind;
CREATE TABLE cells AS
  SELECT cx, cy, ST_MakeEnvelope(cx * %[10]f, cy * %[10]f, (cx + 1) * %[10]f, (cy + 1) * %[10]f) AS g
  FROM range(%[11]d, %[12]d) t1(cx), range(%[13]d, %[14]d) t2(cy);
COPY (
  SELECT cx, cy, kind, ST_AsGeoJSON(d.geom)::JSON AS geom FROM (
    SELECT c.cx, c.cy, m.kind, unnest(ST_Dump(ST_SimplifyPreserveTopology(ST_Intersection(m.g, c.g), %[16]f))) AS d
    FROM merged m JOIN cells c ON ST_Intersects(m.g, c.g)
  ) WHERE ST_GeometryType(d.geom) = 'POLYGON' AND ST_Area(d.geom) >= %[17]f
) TO %[15]s (FORMAT json);
`, area, pb.GroundKind_WATER, proj, duck.Quote(e.Raw("water")),
		pb.GroundKind_PLAZA, pb.GroundKind_RAIL, pb.GroundKind_PARK, duck.Quote(e.Raw("land_use")), duck.Quote(e.Raw("land")),
		cm, x0, x1+1, y0, y1+1, duck.Quote(out+".tmp"), e.C.Tuning.Ground.SimplifyM, e.C.Tuning.Ground.MinAreaM2)
	if _, err := duck.Exec("ground", sql); err != nil {
		return err
	}
	return os.Rename(out+".tmp", out)
}

// chunkRange is the inclusive chunk index range covering the area.
func (e *Env) chunkRange() (x0, y0, x1, y1 int) {
	cm := float64(e.C.Tuning.ChunkM)
	minX, minY, maxX, maxY := math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)
	for _, p := range e.AreaRingM() {
		minX, maxX = math.Min(minX, p.X), math.Max(maxX, p.X)
		minY, maxY = math.Min(minY, p.Y), math.Max(maxY, p.Y)
	}
	return int(math.Floor(minX / cm)), int(math.Floor(minY / cm)), int(math.Floor(maxX / cm)), int(math.Floor(maxY / cm))
}

// LoadGround reads ground.jsonl plus the pedestrian-zone paving (zones_ground.jsonl, if built).
func (e *Env) LoadGround() ([]GroundRow, error) {
	f, err := os.Open(e.W("ground.jsonl"))
	if err != nil {
		return nil, fmt.Errorf("ground.jsonl missing, run ground first: %w", err)
	}
	out, err := readGround(f)
	f.Close()
	if err != nil {
		return nil, err
	}
	z, err := os.Open(e.W("zones_ground.jsonl"))
	if os.IsNotExist(err) {
		return out, nil
	}
	if err != nil {
		return nil, err
	}
	defer z.Close()
	more, err := readGround(z)
	return append(out, more...), err
}

func readGround(f *os.File) ([]GroundRow, error) {
	var out []GroundRow
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<28)
	for sc.Scan() {
		var r struct {
			CX, CY int
			Kind   int
			Geom   struct {
				Coordinates [][][2]float64 `json:"coordinates"`
			} `json:"geom"`
		}
		if err := json.Unmarshal(sc.Bytes(), &r); err != nil {
			return nil, err
		}
		g := GroundRow{CX: r.CX, CY: r.CY, Kind: pb.GroundKind(r.Kind)}
		for i, ring := range r.Geom.Coordinates {
			pts := make([]geo.Pt, len(ring))
			for j, c := range ring {
				pts[j] = geo.Pt{X: c[0], Y: c[1]}
			}
			pts = geo.OpenRing(pts)
			if len(pts) >= 3 {
				g.Rings = append(g.Rings, geo.Canonical(geo.Orient(pts, i == 0)))
			}
		}
		if len(g.Rings) > 0 {
			out = append(out, g)
		}
	}
	return out, sc.Err()
}
