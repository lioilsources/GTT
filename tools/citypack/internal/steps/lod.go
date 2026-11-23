package steps

import (
	"bufio"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"log/slog"
	"math"
	"os"
	"path/filepath"
	"sort"

	"citypack/internal/duck"
	"citypack/internal/geo"
	"citypack/internal/pb"
)

// Lod writes lod/{x}_{y}.pb for the chase camera's far ring (specs/terrain.md, specs/nature.md):
// per lod_chunks × lod_chunks chunks a 32 m terrain, buildings merged into block masses, wood and
// parkland as low green masses and the water as one surface. It adds the tiles to the manifest.
func Lod(e *Env) error {
	tg, _, err := e.LoadTerrain()
	if err != nil {
		return err
	}
	dir := filepath.Join(e.Out, "lod")
	old, _ := filepath.Glob(filepath.Join(dir, "*.pb"))
	for _, f := range old {
		_ = os.Remove(f)
	}
	man := &pb.Manifest{}
	if err := ReadPB(filepath.Join(e.Out, "manifest.pb"), man); err != nil {
		return err
	}
	man.Lods, man.LodChunks, man.LodGridM = nil, 0, 0
	if tg == nil {
		_, err := writePBSize(filepath.Join(e.Out, "manifest.pb"), man)
		return err
	}
	lt := e.C.Tuning.Terrain.Lod
	nc := lt.Chunks
	cm := float64(e.C.Tuning.ChunkM)
	tile := float64(nc) * cm
	x0, y0, x1, y1 := e.chunkRange()
	lx0, ly0 := floorDiv(x0, nc), floorDiv(y0, nc)
	lx1, ly1 := floorDiv(x1, nc), floorDiv(y1, nc)
	rowsPath := e.W("lod.jsonl")
	greenSel := "SELECT NULL::INT AS kind, NULL::GEOMETRY AS g WHERE false"
	waterSel := "SELECT NULL::GEOMETRY AS g WHERE false"
	if _, err := os.Stat(e.W("nature_green.jsonl")); err == nil {
		greenSel = fmt.Sprintf(`SELECT CASE cls WHEN %d THEN %d ELSE %d END AS kind, ST_GeomFromGeoJSON(geom::VARCHAR) AS g
  FROM read_json(%s, format='newline_delimited', columns={cls: 'INT', geom: 'JSON'}) WHERE cls IN (%d, %d)`,
			pb.GreenClass_GREEN_WOOD, pb.LodKind_LOD_WOOD, pb.LodKind_LOD_PARKLAND, duck.Quote(e.W("nature_green.jsonl")),
			pb.GreenClass_GREEN_WOOD, pb.GreenClass_GREEN_PARKLAND)
		waterSel = fmt.Sprintf(`SELECT ST_GeomFromGeoJSON(geom::VARCHAR) AS g FROM read_json(%s, format='newline_delimited', columns={geom: 'JSON'})`,
			duck.Quote(e.W("nature_water.jsonl")))
	}
	m := lt.BlockMergeM
	sql := fmt.Sprintf(`
CREATE TABLE cells AS
  SELECT lx, ly, ST_MakeEnvelope(lx * %[1]f, ly * %[1]f, (lx + 1) * %[1]f, (ly + 1) * %[1]f) AS g
  FROM range(%[2]d, %[3]d) t1(lx), range(%[4]d, %[5]d) t2(ly);
CREATE TABLE b AS SELECT ST_MakeValid(ST_GeomFromGeoJSON(geom::VARCHAR)) AS g, h
  FROM read_json(%[6]s, format='newline_delimited', columns={h: 'DOUBLE', mh: 'DOUBLE', geom: 'JSON'}) WHERE mh < 0.5;
CREATE TABLE bc AS SELECT *, ST_ClusterDBSCAN(g, %[7]f, 1) OVER () AS cl FROM b;
CREATE TABLE blocks AS
  SELECT ST_MakeValid(ST_Buffer(ST_MakeValid(ST_Buffer(ST_Union_Agg(g), %[8]f, 2, 'CAP_SQUARE', 'JOIN_MITRE', 5.0)), -%[8]f, 2, 'CAP_SQUARE', 'JOIN_MITRE', 5.0)) AS g,
         sum(h * ST_Area(g)) / sum(ST_Area(g)) AS h
  FROM bc GROUP BY cl;
CREATE TABLE green AS SELECT kind, ST_Union_Agg(ST_MakeValid(g)) AS g FROM (%[9]s) GROUP BY kind;
CREATE TABLE water AS SELECT ST_Union_Agg(ST_MakeValid(g)) AS g FROM (%[10]s);
COPY (
  SELECT * FROM (
    SELECT lx, ly, %[11]d AS kind, round(h, 1) AS h, ST_AsGeoJSON(d.geom)::JSON AS geom FROM (
      SELECT c.lx, c.ly, b.h, unnest(ST_Dump(ST_SimplifyPreserveTopology(ST_Intersection(b.g, c.g), %[12]f))) AS d
      FROM blocks b JOIN cells c ON ST_Intersects(b.g, c.g))
    WHERE ST_GeometryType(d.geom) = 'POLYGON' AND ST_Area(d.geom) >= 50
    UNION ALL
    SELECT lx, ly, kind, 0, ST_AsGeoJSON(d.geom)::JSON FROM (
      SELECT c.lx, c.ly, gr.kind, unnest(ST_Dump(ST_SimplifyPreserveTopology(ST_Intersection(gr.g, c.g), %[12]f))) AS d
      FROM green gr JOIN cells c ON ST_Intersects(gr.g, c.g))
    WHERE ST_GeometryType(d.geom) = 'POLYGON' AND ST_Area(d.geom) >= 200
    UNION ALL
    SELECT lx, ly, -1, 0, ST_AsGeoJSON(d.geom)::JSON FROM (
      SELECT c.lx, c.ly, unnest(ST_Dump(ST_SimplifyPreserveTopology(ST_Intersection(w.g, c.g), %[12]f))) AS d
      FROM water w JOIN cells c ON w.g IS NOT NULL AND ST_Intersects(w.g, c.g))
    WHERE ST_GeometryType(d.geom) = 'POLYGON' AND ST_Area(d.geom) >= 50
  ) ORDER BY ALL
) TO %[13]s (FORMAT json);
`, tile, lx0, lx1+1, ly0, ly1+1, duck.Quote(e.W("buildings.jsonl")), 2*m, m, greenSel, waterSel,
		pb.LodKind_LOD_BLOCK, lt.SimplifyM, duck.Quote(rowsPath))
	if _, err := duck.Exec("lod", sql); err != nil {
		return err
	}
	f, err := os.Open(rowsPath)
	if err != nil {
		return err
	}
	defer f.Close()
	tiles := map[[2]int]*pb.Lod{}
	get := func(x, y int) *pb.Lod {
		k := [2]int{x, y}
		if t := tiles[k]; t != nil {
			return t
		}
		t := &pb.Lod{X: int32(x), Y: int32(y)}
		tiles[k] = t
		return t
	}
	heights := map[pb.LodKind]float64{
		pb.LodKind_LOD_WOOD: e.C.Tuning.Nature.Wood.CanopyHeightM, pb.LodKind_LOD_PARKLAND: lt.ParklandHeightM,
	}
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<28)
	masses := 0
	for sc.Scan() {
		var r struct {
			LX, LY int
			Kind   int
			H      float64
			Geom   struct {
				Coordinates [][][2]float64 `json:"coordinates"`
			} `json:"geom"`
		}
		if err := json.Unmarshal(sc.Bytes(), &r); err != nil {
			return err
		}
		rs := rings(r.Geom.Coordinates)
		if len(rs) == 0 {
			continue
		}
		idx, err := geo.Triangulate(rs)
		if err != nil || len(idx) == 0 {
			continue
		}
		t := get(r.LX, r.LY)
		if r.Kind < 0 {
			mesh := &pb.Mesh{Kind: pb.GroundKind_WATER}
			for _, ring := range rs {
				for _, p := range ring {
					mesh.Vertices = append(mesh.Vertices, geo.DM(p.X), geo.DM(p.Y))
				}
			}
			for _, i := range idx {
				mesh.Indices = append(mesh.Indices, uint32(i))
			}
			t.Water = append(t.Water, mesh)
			continue
		}
		kind := pb.LodKind(r.Kind)
		h := r.H
		if kind != pb.LodKind_LOD_BLOCK {
			h = heights[kind]
		}
		lm := &pb.LodMass{Kind: kind, HeightM: float32(h), BaseZDm: baseZ(tg, rs[0])}
		n := 0
		for _, ring := range rs {
			for _, p := range ring {
				lm.Rings = append(lm.Rings, geo.DM(p.X), geo.DM(p.Y))
			}
			n += len(ring)
			lm.RingEnds = append(lm.RingEnds, uint32(n))
		}
		for _, i := range idx {
			lm.Roof = append(lm.Roof, uint32(i))
		}
		t.Masses = append(t.Masses, lm)
		masses++
	}
	if err := sc.Err(); err != nil {
		return err
	}
	// Terrain for every tile that has content, sampled from the 8 m grid.
	gm := lt.GridM
	n := int(math.Round(tile/gm)) + 1
	var keys [][2]int
	for k := range tiles {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i][1] != keys[j][1] {
			return keys[i][1] < keys[j][1]
		}
		return keys[i][0] < keys[j][0]
	})
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	total := 0
	for _, k := range keys {
		t := tiles[k]
		t.Terrain = make([]byte, 2*n*n)
		for j := 0; j < n; j++ {
			for i := 0; i < n; i++ {
				p := geo.Pt{X: float64(k[0])*tile + float64(i)*gm, Y: float64(k[1])*tile + float64(j)*gm}
				binary.LittleEndian.PutUint16(t.Terrain[2*(j*n+i):], uint16(int16(geo.DM(tg.At(p)))))
			}
		}
		b, err := writePBSize(filepath.Join(dir, fmt.Sprintf("%d_%d.pb", k[0], k[1])), t)
		if err != nil {
			return err
		}
		total += b
		man.Lods = append(man.Lods, &pb.ChunkRef{X: int32(k[0]), Y: int32(k[1]), Bytes: uint32(b), Buildings: uint32(len(t.Masses))})
	}
	man.LodChunks = uint32(nc)
	man.LodGridM = uint32(math.Round(gm))
	if _, err := writePBSize(filepath.Join(e.Out, "manifest.pb"), man); err != nil {
		return err
	}
	slog.Info("lod", "tiles", len(keys), "masses", masses, "kB", total/1024)
	return nil
}

func floorDiv(a, b int) int {
	q := a / b
	if (a%b != 0) && ((a < 0) != (b < 0)) {
		q--
	}
	return q
}
