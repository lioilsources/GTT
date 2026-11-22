package steps

import (
	"bytes"
	"compress/gzip"
	"fmt"
	"hash/fnv"
	"log/slog"
	"math"
	"os"
	"path/filepath"
	"sort"

	"citypack/internal/geo"
	"citypack/internal/pb"

	"google.golang.org/protobuf/proto"
	"gopkg.in/yaml.v3"
)

const FormatVersion = 1

var attribution = []string{
	"© OpenStreetMap contributors (ODbL)",
	"Overture Maps Foundation",
}

// Landmarks resolves landmarks.yaml against the building masses into landmarks.pb data.
func Landmarks(e *Env) error {
	masses, err := e.LoadMasses()
	if err != nil {
		return err
	}
	maxH := map[int]float64{}
	for _, m := range masses {
		if m.Landmark > 0 {
			maxH[m.Landmark] = math.Max(maxH[m.Landmark], m.HeightM)
		}
	}
	lms := &pb.Landmarks{}
	for i, l := range e.C.Landmarks {
		p := e.Proj.Forward(l.Lon, l.Lat)
		h := l.HeightM
		if h == 0 {
			h = maxH[i+1]
		}
		lms.Items = append(lms.Items, &pb.Landmark{
			Id: l.ID, Name: l.Name, X: geo.DM(p.X), Y: geo.DM(p.Y), HeightM: float32(h), Hero: l.Hero, Blurb: l.Blurb,
		})
	}
	return writePB(e.W("landmarks.pb"), lms, false)
}

// Spots snaps curated points and the start onto the nearest kept edge (METROPOLE_PLAN 5.3 step 7).
func Spots(e *Env) error {
	g, err := e.LoadGraph()
	if err != nil {
		return err
	}
	sp := &pb.Spots{}
	for _, s := range e.C.Spots {
		p := e.Proj.Forward(s.Lon, s.Lat)
		ei, q, dir := nearestKept(g, p)
		if ei < 0 {
			return fmt.Errorf("spot %s: no kept road", s.ID)
		}
		if d := q.Dist(p); d > 250 {
			slog.Warn("spot far from kept road", "id", s.ID, "m", int(d))
		}
		sp.Items = append(sp.Items, &pb.Spot{
			Id: s.ID, Kind: s.Kind, Name: s.Name, Minigame: s.Minigame, X: geo.DM(p.X), Y: geo.DM(p.Y),
			Edge: uint32(ei), ParkX: geo.DM(q.X), ParkY: geo.DM(q.Y), ParkHeading: float32(math.Atan2(dir.Y, dir.X)),
		})
	}
	return writePB(e.W("spots.pb"), sp, false)
}

// nearestKept returns the nearest kept edge, the closest point on it and its direction there.
func nearestKept(g *pb.Graph, p geo.Pt) (int, geo.Pt, geo.Pt) {
	return nearestKeptNamed(g, p, "")
}

// nearestKeptNamed is nearestKept restricted to edges called name (any name when empty).
func nearestKeptNamed(g *pb.Graph, p geo.Pt, name string) (int, geo.Pt, geo.Pt) {
	best, bestD := -1, math.Inf(1)
	var bq, bdir geo.Pt
	for i, ed := range g.Edges {
		if !ed.Kept || ed.Tunnel || ed.LayerFrom != 0 || ed.LayerTo != 0 {
			continue
		}
		if name != "" && g.Names[ed.Name] != name {
			continue
		}
		pts := EdgePts(ed)
		for j := 1; j < len(pts); j++ {
			q, _ := geo.ClosestOnSegment(p, pts[j-1], pts[j])
			if d := q.Dist(p); d < bestD {
				best, bestD, bq, bdir = i, d, q, pts[j].Sub(pts[j-1])
			}
		}
	}
	return best, bq, bdir
}

type districtFile struct {
	Grid struct {
		Anchor       struct{ Lat, Lon float64 } `yaml:"anchor"`
		AnchorStreet float64                    `yaml:"anchor_street"`
		BearingDeg   float64                    `yaml:"bearing_deg"`
		StreetM      float64                    `yaml:"street_m"`
		AvenuesM     map[string]float64         `yaml:"avenues_m"`
	} `yaml:"grid"`
	Districts []struct {
		Name    string       `yaml:"name"`
		Streets [2]float64   `yaml:"streets"`
		Avenues [2]string    `yaml:"avenues"`
		Ring    [][2]float64 `yaml:"ring"` // lon, lat; alternative to grid rectangles
	} `yaml:"districts"`
}

func (e *Env) loadDistricts() ([]*pb.District, error) {
	if e.C.City.DistrictsFile == "" {
		return nil, nil
	}
	b, err := os.ReadFile(filepath.Join(e.C.City.Dir, e.C.City.DistrictsFile))
	if err != nil {
		return nil, err
	}
	var df districtFile
	if err := yaml.Unmarshal(b, &df); err != nil {
		return nil, fmt.Errorf("districts: %w", err)
	}
	gr := df.Grid
	anchor := e.Proj.Forward(gr.Anchor.Lon, gr.Anchor.Lat)
	br := gr.BearingDeg * math.Pi / 180
	up := geo.Pt{X: math.Sin(br), Y: math.Cos(br)}    // along avenues, uptown
	east := geo.Pt{X: math.Cos(br), Y: -math.Sin(br)} // along streets, east
	at := func(street float64, ave string) (geo.Pt, error) {
		off, ok := gr.AvenuesM[ave]
		if !ok {
			return geo.Pt{}, fmt.Errorf("districts: unknown avenue %q", ave)
		}
		return anchor.Add(up.Mul((street - gr.AnchorStreet) * gr.StreetM)).Add(east.Mul(off)), nil
	}
	var out []*pb.District
	for _, d := range df.Districts {
		var ring []geo.Pt
		if len(d.Ring) > 0 {
			for _, c := range d.Ring {
				ring = append(ring, e.Proj.Forward(c[0], c[1]))
			}
		} else {
			for _, c := range [][2]int{{0, 0}, {0, 1}, {1, 1}, {1, 0}} {
				p, err := at(d.Streets[c[0]], d.Avenues[c[1]])
				if err != nil {
					return nil, err
				}
				ring = append(ring, p)
			}
		}
		pd := &pb.District{Name: d.Name}
		for _, p := range geo.Orient(geo.OpenRing(ring), true) {
			pd.Ring = append(pd.Ring, geo.DM(p.X), geo.DM(p.Y))
		}
		out = append(out, pd)
	}
	return out, nil
}

// Pack writes the final citypack: manifest, graph, chunks, landmarks, spots (all gzip protobuf).
func Pack(e *Env) error {
	g, err := e.LoadGraph()
	if err != nil {
		return err
	}
	masses, err := e.LoadMasses()
	if err != nil {
		return err
	}
	ground, err := e.LoadGround()
	if err != nil {
		return err
	}
	// DuckDB returns rows in no fixed order; sort so the same input packs to the same bytes.
	for i := range masses {
		holes := masses[i].Rings[1:]
		sort.Slice(holes, func(a, b int) bool { return ptLess(holes[a][0], holes[b][0]) })
	}
	sort.Slice(masses, func(i, j int) bool { return massLess(masses[i], masses[j]) })
	sort.Slice(ground, func(i, j int) bool { return groundLess(ground[i], ground[j]) })
	// Exact duplicates (a building listed twice in the source) would z-fight; keep one.
	uniq := masses[:0]
	for i, m := range masses {
		if i > 0 && !massLess(masses[i-1], m) && !massLess(m, masses[i-1]) {
			continue
		}
		uniq = append(uniq, m)
	}
	if d := len(masses) - len(uniq); d > 0 {
		slog.Info("pack: dropped duplicate masses", "count", d)
	}
	masses = uniq
	cm := float64(e.C.Tuning.ChunkM)
	chunks := map[[2]int]*pb.Chunk{}
	chunk := func(x, y int) *pb.Chunk {
		k := [2]int{x, y}
		if c, ok := chunks[k]; ok {
			return c
		}
		c := &pb.Chunk{X: int32(x), Y: int32(y)}
		chunks[k] = c
		return c
	}
	failed := 0
	for _, m := range masses {
		b, err := buildingPB(m)
		if err != nil {
			failed++
			continue
		}
		c := centroid(m.Rings[0])
		ch := chunk(int(math.Floor(c.X/cm)), int(math.Floor(c.Y/cm)))
		ch.Buildings = append(ch.Buildings, b)
	}
	for _, gr := range ground {
		idx, err := geo.Triangulate(gr.Rings)
		if err != nil || len(idx) == 0 {
			failed++
			continue
		}
		mesh := &pb.Mesh{Kind: gr.Kind}
		for _, r := range gr.Rings {
			for _, p := range r {
				mesh.Vertices = append(mesh.Vertices, geo.DM(p.X), geo.DM(p.Y))
			}
		}
		for _, i := range idx {
			mesh.Indices = append(mesh.Indices, uint32(i))
		}
		ch := chunk(gr.CX, gr.CY)
		ch.Ground = append(ch.Ground, mesh)
	}
	if failed > 0 {
		slog.Warn("pack: polygons failed to triangulate", "count", failed)
	}
	barriers, err := e.LoadZoneBarriers()
	if err != nil {
		return err
	}
	for i := range barriers {
		// Canonical direction so the same input packs to the same bytes.
		b := barriers[i].Pts
		if ptLess(b[len(b)-1], b[0]) {
			for l, r := 0, len(b)-1; l < r; l, r = l+1, r-1 {
				b[l], b[r] = b[r], b[l]
			}
		}
	}
	sort.Slice(barriers, func(i, j int) bool { return barrierLess(barriers[i], barriers[j]) })
	for _, br := range barriers {
		bar := &pb.Barrier{}
		for _, p := range br.Pts {
			bar.Points = append(bar.Points, geo.DM(p.X), geo.DM(p.Y))
		}
		ch := chunk(br.CX, br.CY)
		ch.Barriers = append(ch.Barriers, bar)
	}
	if err := os.MkdirAll(filepath.Join(e.Out, "chunks"), 0o755); err != nil {
		return err
	}
	// Remove stale chunks from an earlier build.
	old, _ := filepath.Glob(filepath.Join(e.Out, "chunks", "*.pb"))
	for _, f := range old {
		_ = os.Remove(f)
	}
	keys := make([][2]int, 0, len(chunks))
	for k := range chunks {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i][1] != keys[j][1] {
			return keys[i][1] < keys[j][1]
		}
		return keys[i][0] < keys[j][0]
	})
	man := &pb.Manifest{
		FormatVersion: FormatVersion, CityId: e.C.City.ID, Name: e.C.City.Name,
		OriginLat: e.C.City.Origin.Lat, OriginLon: e.C.City.Origin.Lon,
		DriveSide: e.C.City.DriveSide, Units: e.C.City.Units, OvertureRelease: e.C.City.OvertureRelease,
		ChunkM: uint32(e.C.Tuning.ChunkM), Attribution: attribution,
	}
	area := e.AreaRingM()
	minX, minY, maxX, maxY := math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)
	for _, p := range area {
		man.Area = append(man.Area, geo.DM(p.X), geo.DM(p.Y))
		minX, maxX = math.Min(minX, p.X), math.Max(maxX, p.X)
		minY, maxY = math.Min(minY, p.Y), math.Max(maxY, p.Y)
	}
	man.Bounds = &pb.Rect{MinX: geo.DM(minX), MinY: geo.DM(minY), MaxX: geo.DM(maxX), MaxY: geo.DM(maxY)}
	totalBytes := 0
	for _, k := range keys {
		c := chunks[k]
		n, err := writePBSize(filepath.Join(e.Out, "chunks", fmt.Sprintf("%d_%d.pb", k[0], k[1])), c)
		if err != nil {
			return err
		}
		totalBytes += n
		man.Chunks = append(man.Chunks, &pb.ChunkRef{X: int32(k[0]), Y: int32(k[1]), Bytes: uint32(n), Buildings: uint32(len(c.Buildings))})
	}
	// Start: snap onto the nearest kept road, heading along it closest to the configured bearing.
	st := e.C.City.Start
	sp := e.Proj.Forward(st.Lon, st.Lat)
	ei, q, dir := nearestKeptNamed(g, sp, st.Street)
	if ei < 0 {
		return fmt.Errorf("start: no kept road named %q", st.Street)
	}
	hd := (90 - st.HeadingDeg) * math.Pi / 180
	want := geo.Pt{X: math.Cos(hd), Y: math.Sin(hd)}
	if dir.Dot(want) < 0 {
		dir = dir.Mul(-1)
	}
	man.Start = &pb.Spawn{X: geo.DM(q.X), Y: geo.DM(q.Y), HeadingRad: float32(math.Atan2(dir.Y, dir.X))}
	if man.Districts, err = e.loadDistricts(); err != nil {
		return err
	}
	for _, f := range []struct {
		name string
		msg  proto.Message
	}{{"graph.pb", g}, {"manifest.pb", man}} {
		n, err := writePBSize(filepath.Join(e.Out, f.name), f.msg)
		if err != nil {
			return err
		}
		totalBytes += n
	}
	for _, name := range []string{"landmarks.pb", "spots.pb"} {
		b, err := os.ReadFile(e.W(name))
		if err != nil {
			return err
		}
		n, err := writeGz(filepath.Join(e.Out, name), b)
		if err != nil {
			return err
		}
		totalBytes += n
	}
	slog.Info("pack", "chunks", len(keys), "buildings", len(masses), "MB", fmt.Sprintf("%.1f", float64(totalBytes)/1e6), "out", e.Out)
	return nil
}

func ptLess(a, b geo.Pt) bool {
	if a.X != b.X {
		return a.X < b.X
	}
	return a.Y < b.Y
}

// massLess is a total order (heights, then every vertex), so ties never depend on input order.
func massLess(a, b MassRow) bool {
	if a.MinH != b.MinH {
		return a.MinH < b.MinH
	}
	if a.HeightM != b.HeightM {
		return a.HeightM < b.HeightM
	}
	return ringsLess(a.Rings, b.Rings)
}

func ringsLess(a, b [][]geo.Pt) bool {
	for i := 0; i < len(a) && i < len(b); i++ {
		for j := 0; j < len(a[i]) && j < len(b[i]); j++ {
			if a[i][j] != b[i][j] {
				return ptLess(a[i][j], b[i][j])
			}
		}
		if len(a[i]) != len(b[i]) {
			return len(a[i]) < len(b[i])
		}
	}
	return len(a) < len(b)
}

func barrierLess(a, b BarrierRow) bool {
	if a.CX != b.CX {
		return a.CX < b.CX
	}
	if a.CY != b.CY {
		return a.CY < b.CY
	}
	for i := 0; i < len(a.Pts) && i < len(b.Pts); i++ {
		if a.Pts[i] != b.Pts[i] {
			return ptLess(a.Pts[i], b.Pts[i])
		}
	}
	return len(a.Pts) < len(b.Pts)
}

func groundLess(a, b GroundRow) bool {
	if a.CX != b.CX {
		return a.CX < b.CX
	}
	if a.CY != b.CY {
		return a.CY < b.CY
	}
	if a.Kind != b.Kind {
		return a.Kind < b.Kind
	}
	return ringsLess(a.Rings, b.Rings)
}

func buildingPB(m MassRow) (*pb.Building, error) {
	idx, err := geo.Triangulate(m.Rings)
	if err != nil {
		return nil, err
	}
	if len(idx) == 0 {
		return nil, fmt.Errorf("empty triangulation")
	}
	b := &pb.Building{
		HeightM: float32(m.HeightM), MinHeightM: float32(m.MinH),
		Landmark: uint32(m.Landmark), Collide: m.MinH < 0.5,
	}
	// Seed from the geometry, not the source id: merged masses get new ids on every run.
	h := fnv.New32a()
	fmt.Fprintf(h, "%d %d %.1f", geo.DM(m.Rings[0][0].X), geo.DM(m.Rings[0][0].Y), m.HeightM)
	b.WallSeed = h.Sum32()
	n := 0
	for _, r := range m.Rings {
		for _, p := range r {
			b.Rings = append(b.Rings, geo.DM(p.X), geo.DM(p.Y))
		}
		n += len(r)
		b.RingEnds = append(b.RingEnds, uint32(n))
	}
	for _, i := range idx {
		b.Roof = append(b.Roof, uint32(i))
	}
	return b, nil
}

func centroid(r []geo.Pt) geo.Pt {
	var c geo.Pt
	for _, p := range r {
		c = c.Add(p)
	}
	return c.Mul(1 / float64(len(r)))
}

func writePB(path string, m proto.Message, gz bool) error {
	b, err := proto.Marshal(m)
	if err != nil {
		return err
	}
	if gz {
		_, err = writeGz(path, b)
		return err
	}
	return os.WriteFile(path, b, 0o644)
}

func writePBSize(path string, m proto.Message) (int, error) {
	b, err := proto.Marshal(m)
	if err != nil {
		return 0, err
	}
	return writeGz(path, b)
}

func writeGz(path string, b []byte) (int, error) {
	var buf bytes.Buffer
	zw, _ := gzip.NewWriterLevel(&buf, gzip.BestCompression)
	if _, err := zw.Write(b); err != nil {
		return 0, err
	}
	if err := zw.Close(); err != nil {
		return 0, err
	}
	return buf.Len(), os.WriteFile(path, buf.Bytes(), 0o644)
}

// ReadPB reads a gzip protobuf file from a citypack directory.
func ReadPB(path string, m proto.Message) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	zr, err := gzip.NewReader(f)
	if err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	var buf bytes.Buffer
	if _, err := buf.ReadFrom(zr); err != nil {
		return err
	}
	return proto.Unmarshal(buf.Bytes(), m)
}
