package steps

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"

	"citypack/internal/duck"
	"citypack/internal/geo"
	"citypack/internal/pb"
)

// NaturePiece is one water, green or shore polygon clipped to a chunk cell (nature_*.jsonl).
type NaturePiece struct {
	CX, CY int
	Class  int // pb.WaterClass or pb.GreenClass
	Name   string
	Rings  [][]geo.Pt
}

// NatureName is one named body for labels and spots.area_name (nature_names.jsonl).
type NatureName struct {
	Name  string
	Water bool
	Class int
	AreaM float64      // m²
	Rings [][][]geo.Pt // polygons, each outer ring + holes
}

// Nature classifies water and green from Overture base (specs/nature.md, plan ch. 4 as amended by
// FLOW: no wood masses, no corridors), cuts green by roads, buildings and water, adds the shore
// band, names, and then places trees (nature_trees.go).
func Nature(e *Env) error {
	out := e.W("nature_names.jsonl")
	if e.fresh(out) {
		skip("nature", out)
		return nil
	}
	return e.natureSQL()
}

// Trees is the trees part of the nature step (cached separately: it downloads the inventory).
func Trees(e *Env) error {
	out := e.W("nature_trees.json")
	if e.fresh(out) {
		skip("trees", out)
		return nil
	}
	return e.Trees()
}

func (e *Env) natureSQL() error {
	np := e.C.Tuning.Nature.Pipeline
	cm := float64(e.C.Tuning.ChunkM)
	x0, y0, x1, y1 := e.chunkRange()
	area := e.projSQL("ST_GeomFromText(" + duck.Quote(e.C.City.AreaWKT()) + ")")
	proj := e.projSQL("geometry")
	byName := "cls"
	if len(e.C.City.WaterClassByName) > 0 {
		var names []string
		for n := range e.C.City.WaterClassByName {
			names = append(names, n)
		}
		sort.Strings(names)
		byName = "CASE"
		for _, n := range names {
			c, ok := pb.WaterClass_value["WATER_"+strings.ToUpper(e.C.City.WaterClassByName[n])]
			if !ok {
				return fmt.Errorf("city.yaml water_class_by_name: unknown class %q", e.C.City.WaterClassByName[n])
			}
			byName += fmt.Sprintf(" WHEN name = %s THEN %d", duck.Quote(n), c)
		}
		byName += " ELSE cls END"
	}
	empty := "ST_GeomFromText('GEOMETRYCOLLECTION EMPTY')"
	sql := fmt.Sprintf(`
CREATE TABLE area AS SELECT %[1]s AS g;
CREATE TABLE env AS SELECT ST_Buffer((SELECT g FROM area), 1500) AS g;
CREATE TABLE cells AS
  SELECT cx, cy, ST_MakeEnvelope(cx * %[2]f, cy * %[2]f, (cx + 1) * %[2]f, (cy + 1) * %[2]f) AS g
  FROM range(%[3]d, %[4]d) t1(cx), range(%[5]d, %[6]d) t2(cy);

-- ── Water: classes (specs/nature.md), precedence lake > canal > river > sea, named over unnamed.
CREATE TABLE wraw AS
  SELECT subtype, class, %[39]s AS name, ST_MakeValid(%[7]s) AS g FROM read_parquet(%[8]s)
  WHERE ST_GeometryType(geometry) IN ('POLYGON', 'MULTIPOLYGON') AND subtype NOT IN ('physical')
    AND class NOT IN ('swimming_pool')
    -- Underground water (tunnel, culvert: Rudolfova štola under Letná) is not on the map.
    AND coalesce(level, 0) >= 0 AND NOT list_contains(map_keys(source_tags), 'tunnel');
DELETE FROM wraw WHERE NOT ST_Intersects(g, (SELECT g FROM env));
CREATE TABLE wcls0 AS SELECT CASE
    WHEN subtype = 'ocean' THEN %[9]d
    WHEN subtype IN ('river', 'stream') THEN %[10]d
    WHEN subtype = 'canal' OR class = 'dock' THEN %[11]d
    ELSE %[12]d END AS cls, name, ST_Intersection(g, (SELECT g FROM env)) AS g FROM wraw;
CREATE TABLE wcls AS SELECT %[13]s AS cls, name, g FROM wcls0;
CREATE TABLE wn AS
  SELECT cls, name, cls * 2 + CASE WHEN name IS NULL THEN 0 ELSE 1 END AS rk, ST_Union_Agg(g) AS g
  FROM wcls GROUP BY cls, name;
CREATE TABLE whi AS SELECT a.rk, ST_Union_Agg(b.g) AS g FROM (SELECT DISTINCT rk FROM wn) a JOIN wn b ON b.rk > a.rk GROUP BY a.rk;
CREATE TABLE wq AS SELECT wn.cls, wn.name, CASE WHEN whi.g IS NULL THEN wn.g ELSE ST_Difference(wn.g, whi.g) END AS g
  FROM wn LEFT JOIN whi USING (rk);
CREATE TABLE wbody AS
  SELECT CASE WHEN ST_Area(d.geom) < %[14]f THEN %[15]d ELSE cls END AS cls, name,
         ST_SimplifyPreserveTopology(d.geom, %[16]f) AS g
  FROM (SELECT cls, name, unnest(ST_Dump(g)) AS d FROM wq) WHERE ST_GeometryType(d.geom) = 'POLYGON';
DELETE FROM wbody WHERE ST_IsEmpty(g);
CREATE TABLE wall AS SELECT ST_Union_Agg(g) AS g FROM wbody;
-- Named water features (centre lines, label-only polygons and points) name unnamed sea/river pieces.
CREATE TABLE wnames AS
  SELECT %[39]s AS name,
         CASE WHEN subtype IN ('river', 'stream') OR class IN ('tidal_channel', 'river', 'stream') THEN %[10]d
              WHEN class IN ('bay', 'strait', 'harbour', 'sound') THEN %[9]d
              WHEN subtype = 'canal' OR class = 'canal' THEN %[11]d ELSE 0 END AS cls,
         %[7]s AS g
  FROM read_parquet(%[8]s)
  WHERE %[39]s IS NOT NULL AND (ST_GeometryType(geometry) IN ('LINESTRING', 'MULTILINESTRING')
    OR (subtype = 'physical' AND class IN ('bay', 'strait', 'harbour', 'sound')))
    AND coalesce(level, 0) >= 0 AND NOT list_contains(map_keys(source_tags), 'tunnel');
DELETE FROM wnames WHERE NOT ST_Intersects(g, (SELECT g FROM env));
CREATE TABLE wpiece0 AS
  SELECT cx, cy, cls, name, d.geom AS g FROM (
    SELECT c.cx, c.cy, b.cls, b.name, unnest(ST_Dump(ST_Intersection(ST_Intersection(b.g, (SELECT g FROM area)), c.g))) AS d
    FROM wbody b JOIN cells c ON ST_Intersects(b.g, c.g)
  ) WHERE ST_GeometryType(d.geom) = 'POLYGON' AND ST_Area(d.geom) >= 1.0;
CREATE TABLE wpiece1 AS SELECT row_number() OVER (ORDER BY cx, cy, cls, ST_XMin(g), ST_YMin(g)) AS pid, * FROM wpiece0;
CREATE TABLE wnear AS
  SELECT p.pid, arg_min(n.name, ST_Distance(ST_PointOnSurface(p.g), n.g) * 1e3 + hash(n.name) %% 1000) AS name,
         arg_min(n.cls, ST_Distance(ST_PointOnSurface(p.g), n.g) * 1e3 + hash(n.name) %% 1000) AS ncls
  FROM wpiece1 p JOIN wnames n ON p.name IS NULL AND p.cls IN (%[9]d, %[10]d, %[11]d) AND ST_DWithin(ST_PointOnSurface(p.g), n.g, %[17]f)
  GROUP BY p.pid;
CREATE TABLE wpiece AS
  SELECT p.cx, p.cy, CASE WHEN p.name IS NULL AND w.ncls > 0 THEN w.ncls ELSE p.cls END AS cls0,
         coalesce(p.name, w.name) AS name, p.g FROM wpiece1 p LEFT JOIN wnear w USING (pid);
UPDATE wpiece SET cls0 = %[18]s;
COPY (SELECT cx, cy, cls0 AS cls, coalesce(name, '') AS name, ST_AsGeoJSON(g)::JSON AS geom FROM wpiece ORDER BY ALL)
  TO %[19]s (FORMAT json);
-- Shore: the band inside the water along every bank (not along artificial clip lines: the water
-- union reaches 1.5 km past the area).
CREATE TABLE shore AS
  SELECT ST_Difference((SELECT g FROM wall), ST_Buffer((SELECT g FROM wall), -%[20]f, 2)) AS g;
COPY (
  SELECT cx, cy, %[12]d AS cls, '' AS name, ST_AsGeoJSON(d.geom)::JSON AS geom FROM (
    SELECT c.cx, c.cy, unnest(ST_Dump(ST_SimplifyPreserveTopology(ST_Intersection(ST_Intersection(s.g, (SELECT g FROM area)), c.g), 0.5))) AS d
    FROM shore s JOIN cells c ON ST_Intersects(s.g, c.g)
  ) WHERE ST_GeometryType(d.geom) = 'POLYGON' AND ST_Area(d.geom) >= 1.0 ORDER BY ALL
) TO %[21]s (FORMAT json);

-- ── Green: wood > grass, sand > cemetery, garden > parkland, all minus water, roads, buildings.
CREATE TABLE gsrc AS
  SELECT %[22]d AS cls, %[39]s AS name, ST_MakeValid(%[7]s) AS g FROM read_parquet(%[23]s)
    WHERE subtype = 'forest' AND ST_GeometryType(geometry) IN ('POLYGON', 'MULTIPOLYGON')
  UNION ALL SELECT %[26]d, %[39]s, ST_MakeValid(%[7]s) FROM read_parquet(%[23]s)
    WHERE subtype = 'grass' AND ST_GeometryType(geometry) IN ('POLYGON', 'MULTIPOLYGON')
  UNION ALL SELECT %[27]d, %[39]s, ST_MakeValid(%[7]s) FROM read_parquet(%[23]s)
    WHERE subtype = 'sand' AND ST_GeometryType(geometry) IN ('POLYGON', 'MULTIPOLYGON')
  UNION ALL SELECT %[28]d, %[39]s, ST_MakeValid(%[7]s) FROM read_parquet(%[23]s)
    WHERE subtype = 'shrub' AND ST_GeometryType(geometry) IN ('POLYGON', 'MULTIPOLYGON')
  UNION ALL SELECT CASE
      WHEN subtype = 'cemetery' THEN %[24]d
      WHEN subtype = 'horticulture' THEN %[25]d
      WHEN subtype = 'managed' OR class IN ('grass', 'meadow', 'pitch', 'village_green', 'green', 'driving_range', 'golf_course') THEN %[26]d
      WHEN class = 'forest' OR class = 'wood' THEN %[22]d
      ELSE %[28]d END, %[39]s, ST_MakeValid(%[7]s) FROM read_parquet(%[29]s)
    WHERE (subtype IN ('park', 'cemetery', 'horticulture', 'managed', 'golf', 'protected')
        OR class IN ('recreation_ground', 'pitch', 'meadow', 'zoo', 'village_green'))
      AND ST_GeometryType(geometry) IN ('POLYGON', 'MULTIPOLYGON');
DELETE FROM gsrc WHERE NOT ST_Intersects(g, (SELECT g FROM area));
-- Big parks without inner surfaces take their wood from land_cover (ESA WorldCover).
CREATE TABLE parks AS SELECT g FROM gsrc WHERE cls = %[28]d AND ST_Area(g) > %[30]f;
CREATE TABLE inner_u AS SELECT coalesce(ST_Union_Agg(g), %[33]s) AS g FROM gsrc WHERE cls IN (%[22]d, %[26]d, %[27]d);
CREATE TABLE bare AS SELECT p.g FROM parks p
  WHERE coalesce(ST_Area(ST_Intersection(p.g, (SELECT g FROM inner_u))), 0) + coalesce(ST_Area(ST_Intersection(p.g, (SELECT g FROM wall))), 0) < 0.1 * ST_Area(p.g);
INSERT INTO gsrc SELECT %[22]d, NULL, d.geom FROM (
  SELECT unnest(ST_Dump(ST_Intersection(ST_MakeValid(%[7]s), b.g))) AS d FROM read_parquet(%[31]s) lc JOIN bare b ON ST_Intersects(ST_MakeValid(%[7]s), b.g)
  WHERE lc.subtype = 'forest'
) WHERE ST_GeometryType(d.geom) = 'POLYGON' AND ST_Area(d.geom) > %[32]f;
CREATE TABLE grank AS SELECT cls, CASE cls WHEN %[22]d THEN 5 WHEN %[26]d THEN 4 WHEN %[27]d THEN 4
  WHEN %[24]d THEN 3 WHEN %[25]d THEN 3 ELSE 1 END AS rk FROM (SELECT DISTINCT cls FROM gsrc);
CREATE TABLE gu AS SELECT s.cls, r.rk, ST_Union_Agg(s.g) AS g FROM gsrc s JOIN grank r USING (cls) GROUP BY s.cls, r.rk;
CREATE TABLE ghi AS SELECT a.cls, ST_Union_Agg(b.g) AS g FROM gu a JOIN gu b ON b.rk > a.rk OR (b.rk = a.rk AND b.cls < a.cls) GROUP BY a.cls;
CREATE TABLE roads AS SELECT ST_Buffer(ST_GeomFromText(wkt), hw::DOUBLE, 4) AS g FROM read_csv(%[34]s, header=true, quote='"');
CREATE TABLE bld AS SELECT ST_GeomFromGeoJSON(geom::VARCHAR) AS g FROM read_json(%[35]s, format='newline_delimited', columns={mh: 'DOUBLE', geom: 'JSON'}) WHERE mh < 0.5;
CREATE TABLE gq AS
  SELECT gu.cls, ST_Intersection(CASE WHEN ghi.g IS NULL THEN gu.g ELSE ST_Difference(gu.g, ghi.g) END, (SELECT g FROM area)) AS g
  FROM gu LEFT JOIN ghi USING (cls);
UPDATE gq SET g = ST_Difference(g, (SELECT g FROM wall));
CREATE TABLE gcell0 AS
  SELECT cx, cy, cls, d.geom AS g FROM (
    SELECT c.cx, c.cy, q.cls, unnest(ST_Dump(ST_Intersection(q.g, c.g))) AS d FROM gq q JOIN cells c ON ST_Intersects(q.g, c.g)
  ) WHERE ST_GeometryType(d.geom) = 'POLYGON';
CREATE TABLE gcell1 AS SELECT row_number() OVER (ORDER BY cx, cy, cls, ST_XMin(g), ST_YMin(g)) AS pid, * FROM gcell0;
CREATE TABLE gcut AS
  SELECT p.pid, ST_Union_Agg(x.g) AS g FROM gcell1 p JOIN (SELECT g FROM roads UNION ALL SELECT g FROM bld) x ON ST_Intersects(p.g, x.g) GROUP BY p.pid;
CREATE TABLE gpiece0 AS
  SELECT cx, cy, cls, d.geom AS g FROM (
    SELECT p.cx, p.cy, p.cls, unnest(ST_Dump(ST_SimplifyPreserveTopology(CASE WHEN c.g IS NULL THEN p.g ELSE ST_Difference(p.g, c.g) END, %[16]f))) AS d
    FROM gcell1 p LEFT JOIN gcut c USING (pid)
  ) WHERE ST_GeometryType(d.geom) = 'POLYGON' AND ST_Area(d.geom) >= %[36]f;
-- Names: the named green polygon with the biggest overlap (ties: the smaller polygon).
CREATE TABLE gnames AS SELECT name, g, ST_Area(g) AS a FROM gsrc WHERE name IS NOT NULL;
CREATE TABLE gpiece1 AS SELECT row_number() OVER (ORDER BY cx, cy, cls, ST_XMin(g), ST_YMin(g)) AS pid, * FROM gpiece0;
CREATE TABLE gname AS
  SELECT p.pid, arg_max(n.name, round(ST_Area(ST_Intersection(p.g, n.g)), 1) * 1e9 - n.a) AS name
  FROM gpiece1 p JOIN gnames n ON ST_Intersects(p.g, n.g) GROUP BY p.pid;
CREATE TABLE gpiece AS SELECT p.cx, p.cy, p.cls, coalesce(n.name, '') AS name, p.g FROM gpiece1 p LEFT JOIN gname n USING (pid);
COPY (SELECT cx, cy, cls, name, ST_AsGeoJSON(g)::JSON AS geom FROM gpiece ORDER BY ALL) TO %[37]s (FORMAT json);

-- ── Named bodies for labels and spots: water by (class, name) components, green by name.
COPY (
  SELECT true AS water, cls, name, ST_Area(g) AS area, ST_AsGeoJSON(g)::JSON AS geom FROM (
    SELECT cls0 AS cls, name, ST_Union_Agg(g) AS g FROM wpiece WHERE name IS NOT NULL GROUP BY cls0, name)
  UNION ALL
  SELECT false, 0, name, ST_Area(g), ST_AsGeoJSON(g)::JSON FROM (
    SELECT name, ST_Union_Agg(g) AS g FROM gpiece WHERE name <> '' GROUP BY name)
  ORDER BY water, name, cls
) TO %[38]s (FORMAT json);
`, area, cm, x0, x1+1, y0, y1+1, proj, duck.Quote(e.Raw("water")),
		pb.WaterClass_WATER_SEA, pb.WaterClass_WATER_RIVER, pb.WaterClass_WATER_CANAL, pb.WaterClass_WATER_LAKE,
		strings.ReplaceAll(byName, "cls", "cls"), np.SmallWaterM2, pb.WaterClass_WATER_SMALL, np.SimplifyM, np.WaterNameSearchM,
		strings.ReplaceAll(byName, "cls", "cls0"), duck.Quote(e.W("nature_water.jsonl.tmp")),
		e.C.Tuning.Nature.ShoreBandM, duck.Quote(e.W("nature_shore.jsonl.tmp")),
		pb.GreenClass_GREEN_WOOD, duck.Quote(e.Raw("land")), pb.GreenClass_GREEN_CEMETERY, pb.GreenClass_GREEN_GARDEN,
		pb.GreenClass_GREEN_GRASS, pb.GreenClass_GREEN_SAND, pb.GreenClass_GREEN_PARKLAND, duck.Quote(e.Raw("land_use")),
		np.BigParkHa*1e4, duck.Quote(e.Raw("land_cover")), np.WoodCoverHa*1e4, empty,
		duck.Quote(e.W("road_buffers.csv")), duck.Quote(e.W("buildings.jsonl")), e.C.Tuning.Ground.MinAreaM2,
		duck.Quote(e.W("nature_green.jsonl.tmp")), duck.Quote(e.W("nature_names.jsonl.tmp")), e.C.City.NameSQL())
	if _, err := duck.Exec("nature", sql); err != nil {
		return err
	}
	for _, n := range []string{"nature_water.jsonl", "nature_shore.jsonl", "nature_green.jsonl", "nature_names.jsonl"} {
		if err := os.Rename(e.W(n+".tmp"), e.W(n)); err != nil {
			return err
		}
	}
	return nil
}

// LoadNaturePieces reads nature_water.jsonl, nature_green.jsonl or nature_shore.jsonl.
func (e *Env) LoadNaturePieces(name string) ([]NaturePiece, error) {
	f, err := os.Open(e.W(name))
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var out []NaturePiece
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<28)
	for sc.Scan() {
		var r struct {
			CX, CY int
			Cls    int
			Name   string
			Geom   struct {
				Coordinates [][][2]float64 `json:"coordinates"`
			} `json:"geom"`
		}
		if err := json.Unmarshal(sc.Bytes(), &r); err != nil {
			return nil, err
		}
		p := NaturePiece{CX: r.CX, CY: r.CY, Class: r.Cls, Name: r.Name, Rings: rings(r.Geom.Coordinates)}
		if len(p.Rings) > 0 {
			out = append(out, p)
		}
	}
	return out, sc.Err()
}

// LoadNatureNames reads nature_names.jsonl (named water and green bodies).
func (e *Env) LoadNatureNames() ([]NatureName, error) {
	f, err := os.Open(e.W("nature_names.jsonl"))
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var out []NatureName
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<30)
	for sc.Scan() {
		var r struct {
			Water bool
			Cls   int
			Name  string
			Area  float64
			Geom  json.RawMessage `json:"geom"`
		}
		if err := json.Unmarshal(sc.Bytes(), &r); err != nil {
			return nil, err
		}
		polys, err := geoJSONPolygons(r.Geom)
		if err != nil {
			return nil, err
		}
		out = append(out, NatureName{Name: r.Name, Water: r.Water, Class: r.Cls, AreaM: r.Area, Rings: polys})
	}
	return out, sc.Err()
}

func rings(coords [][][2]float64) [][]geo.Pt {
	var out [][]geo.Pt
	for i, ring := range coords {
		pts := make([]geo.Pt, len(ring))
		for j, c := range ring {
			pts[j] = geo.Pt{X: c[0], Y: c[1]}
		}
		pts = geo.OpenRing(pts)
		if len(pts) < 3 {
			if i == 0 {
				return nil
			}
			continue
		}
		out = append(out, geo.Canonical(geo.Orient(pts, i == 0)))
	}
	return out
}

// geoJSONPolygons reads a Polygon, MultiPolygon or GeometryCollection of them.
func geoJSONPolygons(raw json.RawMessage) ([][][]geo.Pt, error) {
	var g struct {
		Type        string          `json:"type"`
		Coordinates json.RawMessage `json:"coordinates"`
		Geometries  []json.RawMessage
	}
	if err := json.Unmarshal(raw, &g); err != nil {
		return nil, err
	}
	switch g.Type {
	case "Polygon":
		var c [][][2]float64
		if err := json.Unmarshal(g.Coordinates, &c); err != nil {
			return nil, err
		}
		if r := rings(c); len(r) > 0 {
			return [][][]geo.Pt{r}, nil
		}
		return nil, nil
	case "MultiPolygon":
		var c [][][][2]float64
		if err := json.Unmarshal(g.Coordinates, &c); err != nil {
			return nil, err
		}
		var out [][][]geo.Pt
		for _, p := range c {
			if r := rings(p); len(r) > 0 {
				out = append(out, r)
			}
		}
		return out, nil
	case "GeometryCollection":
		var out [][][]geo.Pt
		for _, sub := range g.Geometries {
			p, err := geoJSONPolygons(sub)
			if err != nil {
				return nil, err
			}
			out = append(out, p...)
		}
		return out, nil
	}
	return nil, nil
}

// natureMeshClass maps a green class to its surface (specs/nature.md table).
func greenSurface(c pb.GreenClass) pb.Surface {
	switch c {
	case pb.GreenClass_GREEN_WOOD:
		return pb.Surface_SURFACE_FOREST
	case pb.GreenClass_GREEN_SAND:
		return pb.Surface_SURFACE_SAND
	}
	return pb.Surface_SURFACE_GRASS
}
