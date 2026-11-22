package steps

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"

	"citypack/internal/duck"
	"citypack/internal/geo"
	"citypack/internal/pb"
)

// BarrierRow is one bollard polyline already clipped to a chunk cell (specs/zones.md).
type BarrierRow struct {
	CX, CY int
	Pts    []geo.Pt
}

// Zones builds pedestrian zones (specs/zones.md): corridors around Overture `pedestrian` segments
// plus the pedestrian plazas they cross, minus every road corridor (+ gap margin) so roads stay
// drivable. The zone outline (without the area border) becomes the bollard lines. Output:
// zones_ground.jsonl (PEDESTRIAN paving, same rows as ground.jsonl) and zones_barriers.jsonl.
// Needs road_buffers.csv from widen.
func Zones(e *Env) error {
	paving, barriers := e.W("zones_ground.jsonl"), e.W("zones_barriers.jsonl")
	if e.fresh(paving) && e.fresh(barriers) {
		skip("zones", paving)
		return nil
	}
	if _, err := os.Stat(e.W("road_buffers.csv")); err != nil {
		return fmt.Errorf("zones: road_buffers.csv missing, run widen first: %w", err)
	}
	t := e.C.Tuning
	cm := float64(t.ChunkM)
	x0, y0, x1, y1 := e.chunkRange()
	area := e.projSQL("ST_GeomFromText(" + duck.Quote(e.C.City.AreaWKT()) + ")")
	proj := e.projSQL("geometry")
	sql := fmt.Sprintf(`
CREATE TABLE area AS SELECT %[1]s AS g;
CREATE TABLE seg AS
  SELECT ST_Buffer(%[2]s, %[3]f, 4) AS g FROM read_parquet(%[4]s)
  WHERE subtype = 'road' AND class = 'pedestrian';
CREATE TABLE seg_in AS SELECT g FROM seg WHERE ST_Intersects(g, (SELECT g FROM area));
CREATE TABLE plz AS
  SELECT ST_MakeValid(%[2]s) AS g FROM read_parquet(%[5]s)
  WHERE subtype = 'pedestrian' AND ST_GeometryType(geometry) IN ('POLYGON', 'MULTIPOLYGON');
CREATE TABLE parts AS
  SELECT g FROM seg_in
  UNION ALL SELECT p.g FROM plz p WHERE EXISTS (SELECT 1 FROM seg_in s WHERE ST_Intersects(p.g, s.g));
CREATE TABLE roads AS
  SELECT ST_Buffer(ST_GeomFromText(wkt), hw::DOUBLE + %[6]f, 4) AS g FROM read_csv(%[7]s, header=true, quote='"');
CREATE TABLE zone0 AS SELECT ST_Union_Agg(g) AS g FROM parts;
CREATE TABLE zone AS
  SELECT ST_Intersection(
    ST_Difference(z.g, COALESCE((SELECT ST_Union_Agg(r.g) FROM roads r WHERE ST_Intersects(r.g, z.g)), ST_GeomFromText('POLYGON EMPTY'))),
    (SELECT g FROM area)) AS g
  FROM zone0 z WHERE z.g IS NOT NULL;
CREATE TABLE cells AS
  SELECT cx, cy, ST_MakeEnvelope(cx * %[8]f, cy * %[8]f, (cx + 1) * %[8]f, (cy + 1) * %[8]f) AS g
  FROM range(%[9]d, %[10]d) t1(cx), range(%[11]d, %[12]d) t2(cy);
COPY (
  SELECT cx, cy, %[13]d AS kind, ST_AsGeoJSON(d.geom)::JSON AS geom FROM (
    SELECT c.cx, c.cy, unnest(ST_Dump(ST_SimplifyPreserveTopology(ST_Intersection(z.g, c.g), %[14]f))) AS d
    FROM zone z JOIN cells c ON ST_Intersects(z.g, c.g)
  ) WHERE ST_GeometryType(d.geom) = 'POLYGON' AND ST_Area(d.geom) >= %[15]f
) TO %[16]s (FORMAT json);
CREATE TABLE edge AS
  SELECT ST_Difference(ST_Boundary(z.g), ST_Buffer(ST_Boundary((SELECT g FROM area)), 0.5)) AS g FROM zone z;
COPY (
  SELECT cx, cy, ST_AsGeoJSON(d.geom)::JSON AS geom FROM (
    SELECT c.cx, c.cy, unnest(ST_Dump(ST_LineMerge(ST_Intersection(l.g, c.g)))) AS d
    FROM edge l JOIN cells c ON ST_Intersects(l.g, c.g)
  ) WHERE ST_GeometryType(d.geom) = 'LINESTRING' AND ST_Length(d.geom) >= %[17]f
) TO %[18]s (FORMAT json);
`, area, proj, t.Zones.StreetWidthM/2, duck.Quote(e.Raw("segment")), duck.Quote(e.Raw("land_use")),
		t.Zones.GapMarginM, duck.Quote(e.W("road_buffers.csv")),
		cm, x0, x1+1, y0, y1+1, pb.GroundKind_PEDESTRIAN, t.Ground.SimplifyM, t.Ground.MinAreaM2,
		duck.Quote(paving+".tmp"), t.Zones.MinBarrierM, duck.Quote(barriers+".tmp"))
	if _, err := duck.Exec("zones", sql); err != nil {
		return err
	}
	if err := os.Rename(paving+".tmp", paving); err != nil {
		return err
	}
	return os.Rename(barriers+".tmp", barriers)
}

// LoadZoneBarriers reads zones_barriers.jsonl; a missing file (old work dir) means no barriers.
func (e *Env) LoadZoneBarriers() ([]BarrierRow, error) {
	f, err := os.Open(e.W("zones_barriers.jsonl"))
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var out []BarrierRow
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<26)
	for sc.Scan() {
		var r struct {
			CX, CY int
			Geom   struct {
				Coordinates [][2]float64 `json:"coordinates"`
			} `json:"geom"`
		}
		if err := json.Unmarshal(sc.Bytes(), &r); err != nil {
			return nil, err
		}
		b := BarrierRow{CX: r.CX, CY: r.CY}
		for _, c := range r.Geom.Coordinates {
			b.Pts = append(b.Pts, geo.Pt{X: c[0], Y: c[1]})
		}
		if len(b.Pts) >= 2 {
			out = append(out, b)
		}
	}
	return out, sc.Err()
}
