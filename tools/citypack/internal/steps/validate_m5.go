package steps

import (
	"encoding/binary"
	"fmt"
	"log/slog"
	"math"
	"os"

	"citypack/internal/geo"
	"citypack/internal/pb"
)

// packTerrain decodes Chunk.terrain into a lookup over the whole pack (nil for a flat pack).
type packTerrain struct {
	chunkM, step float64
	n            int
	z            map[[2]int][]int16
}

func newPackTerrain(p *PackData) *packTerrain {
	if p.Manifest.TerrainVersion == 0 || p.Manifest.TerrainGridM == 0 {
		return nil
	}
	cm := float64(p.Manifest.ChunkM)
	t := &packTerrain{chunkM: cm, step: float64(p.Manifest.TerrainGridM), z: map[[2]int][]int16{}}
	t.n = int(math.Round(cm/t.step)) + 1
	for _, c := range p.Chunks {
		if len(c.Terrain) != 2*t.n*t.n {
			continue
		}
		zs := make([]int16, t.n*t.n)
		for i := range zs {
			zs[i] = int16(binary.LittleEndian.Uint16(c.Terrain[2*i:]))
		}
		t.z[[2]int{int(c.X), int(c.Y)}] = zs
	}
	return t
}

// at is the bilinear game height (m) at p from the chunk containing it.
func (t *packTerrain) at(p geo.Pt) (float64, bool) {
	cx, cy := int(math.Floor(p.X/t.chunkM)), int(math.Floor(p.Y/t.chunkM))
	zs, ok := t.z[[2]int{cx, cy}]
	if !ok {
		return 0, false
	}
	x := (p.X - float64(cx)*t.chunkM) / t.step
	y := (p.Y - float64(cy)*t.chunkM) / t.step
	i, j := int(math.Floor(x)), int(math.Floor(y))
	i, j = min(i, t.n-2), min(j, t.n-2)
	fx, fy := x-float64(i), y-float64(j)
	g := func(a, b int) float64 { return float64(zs[b*t.n+a]) / 10 }
	return (g(i, j)*(1-fx)+g(i+1, j)*fx)*(1-fy) + (g(i, j+1)*(1-fx)+g(i+1, j+1)*fx)*fy, true
}

func edgeZ(ed *pb.Edge) []float64 {
	out := make([]float64, len(ed.ZDm))
	for i, z := range ed.ZDm {
		out[i] = float64(z) / 10
	}
	return out
}

// validateTerrain checks the elevation data (specs/terrain.md, plan ch. 4 validate).
func (e *Env) validateTerrain(p *PackData, fail func(string, ...any)) {
	m := p.Manifest
	if m.TerrainVersion == 0 {
		slog.Info("validate: flat pack (no terrain)")
		return
	}
	tt := e.C.Tuning.Terrain
	tol := tt.Pipeline.GradeTolM
	t := newPackTerrain(p)
	n := t.n
	for _, c := range p.Chunks {
		if len(c.Terrain) != 2*n*n || len(c.Shade) != n*n {
			fail("chunk %d_%d: terrain %d B and shade %d B, want %d and %d", c.X, c.Y, len(c.Terrain), len(c.Shade), 2*n*n, n*n)
		}
	}
	// int16 range: no sample saturated.
	sat := 0
	for _, zs := range t.z {
		for _, z := range zs {
			if z == math.MaxInt16 || z == math.MinInt16 {
				sat++
			}
		}
	}
	if sat > 0 {
		fail("%d terrain samples saturate int16", sat)
	}
	g := p.Graph
	// Node heights agree with every edge end; one height per vertex.
	badNode, badLen, steep, stairs := 0, 0, 0, 0
	for i, ed := range g.Edges {
		if len(ed.ZDm) != len(ed.Points)/2 {
			badLen++
			continue
		}
		if ed.ZDm[0] != g.Nodes[ed.From].ZDm || ed.ZDm[len(ed.ZDm)-1] != g.Nodes[ed.To].ZDm {
			badNode++
		}
		if ed.Stairs {
			stairs++
			continue
		}
		grade := tt.MaxGrade[gradeClass(ed)]
		if ed.Bridge {
			grade = math.Min(grade, tt.Bridge.MaxGrade)
		}
		if ed.Tunnel {
			grade = math.Min(grade, tt.Tunnel.MaxGrade)
		}
		pts, zs := EdgePts(ed), edgeZ(ed)
		for k := 1; k < len(pts); k++ {
			l := pts[k].Dist(pts[k-1])
			// Heights are stored in decimetres: allow the rounding plus the clamp tolerance, which
			// holds per profile link (a simplified segment spans l / profile_step of them).
			if math.Abs(zs[k]-zs[k-1]) > grade*l+tol*math.Max(1, math.Ceil(l/tt.Pipeline.ProfileStepM))+0.1 {
				steep++
				if steep <= 10 {
					slog.Warn("validate: edge over max_grade", "edge", i, "name", g.Names[ed.Name], "grade", fmt.Sprintf("%.3f", math.Abs(zs[k]-zs[k-1])/l), "max", grade)
				}
				break
			}
		}
	}
	if badLen > 0 {
		fail("%d edges have a z_dm count different from their points", badLen)
	}
	if badNode > 0 {
		fail("%d edges disagree with their end node heights", badNode)
	}
	if steep > 0 {
		fail("%d edges are steeper than terrain.max_grade", steep)
	}
	// Bridge clearance over water and over ground roads; road edge vs terrain.
	tp := tt.Pipeline
	water := newMeshIndex(p, func(m *pb.Mesh) bool { return m.Kind == pb.GroundKind_WATER })
	ground := groundSegments(p, e.C.Tuning.SidewalkWidthM, t.at, tp.RoadGapMaxM)
	plateau := tt.GridM * math.Sqrt2 // conform's plateau (elevation.go)
	lowDeck, shortDeck, gap, gapN := 0, 0, 0, 0
	// Landings: nodes where a bridge edge meets a ground edge.
	isBridge := func(ed *pb.Edge) bool { return ed.Bridge && (ed.LayerFrom > 0 || ed.LayerTo > 0) }
	nb, ng := make([]bool, len(g.Nodes)), make([]bool, len(g.Nodes))
	for _, ed := range g.Edges {
		for _, n := range []uint32{ed.From, ed.To} {
			if isBridge(ed) {
				nb[n] = true
			} else if groundEdge(ed) {
				ng[n] = true
			}
		}
	}
	var landings []geo.Pt
	for n := range g.Nodes {
		if nb[n] && ng[n] {
			landings = append(landings, geo.Pt{X: float64(g.Nodes[n].X) / 10, Y: float64(g.Nodes[n].Y) / 10})
		}
	}
	// nearLanding: the deck is closer to a landing than the ramp a bridge needs to clear a road
	// (bridge.clear_road_m / bridge.max_grade); a road crossed there meets the deck about at grade
	// (Jiráskův most over Masarykovo nábřeží), so its clearance only warns.
	ramp := tt.Bridge.ClearRoadM / tt.Bridge.MaxGrade
	nearLanding := func(q geo.Pt) bool {
		for _, l := range landings {
			if l.Dist(q) < ramp {
				return true
			}
		}
		return false
	}
	// deck checks one bridge sample against the surface below it: under the hard minimum it
	// fails, under the full clearance it only warns (relaxed pins keep decks near the shore lower).
	deck := func(i int, what string, z, below, want float64, soft bool) {
		switch {
		case z < below+tp.BridgeMinClearM-0.1 && !soft:
			lowDeck++
			if lowDeck <= 10 {
				slog.Warn("validate: bridge too low over "+what, "edge", i, "name", g.Names[g.Edges[i].Name], "deck_m", z, "below_m", below, "min_m", tp.BridgeMinClearM)
			}
		case z < below+want-tol-0.1:
			shortDeck++
			if os.Getenv("CITYPACK_DEBUG") != "" {
				slog.Warn("validate: bridge clearance short over "+what, "edge", i, "name", g.Names[g.Edges[i].Name], "deck_m", z, "below_m", below, "want_m", want)
			}
		}
	}
	for i, ed := range g.Edges {
		pts, zs := EdgePts(ed), edgeZ(ed)
		if len(zs) != len(pts) {
			continue
		}
		if ed.Bridge && ed.LayerFrom > 0 && ed.LayerTo > 0 {
			for k := range pts {
				if w, ok := water.at(pts[k]); ok {
					deck(i, "water", zs[k], float64(w.ZDm)/10, tt.Bridge.ClearWaterM, false)
				}
				for _, s := range ground.near(pts[k]) {
					// A road joined to the bridge climbs to its deck: that is the ramp, not a crossing.
					if s.edge == i || sharesNode(g.Edges[s.edge], ed) {
						continue
					}
					q, tq := geo.ClosestOnSegment(pts[k], s.a, s.b)
					if q.Dist(pts[k]) > s.hw {
						continue
					}
					deck(i, "road "+g.Names[g.Edges[s.edge].Name]+fmt.Sprintf(" (edge %d)", s.edge), zs[k], s.za+(s.zb-s.za)*tq, tt.Bridge.ClearRoadM, nearLanding(pts[k]))
				}
			}
		}
		if !groundEdge(ed) {
			continue
		}
		hw := float64(ed.WidthM) / 2
		for k := 1; k < len(pts); k++ {
			a, b := pts[k-1], pts[k]
			l := a.Dist(b)
			if l < 1e-6 {
				continue
			}
			nrm := geo.Pt{X: -(b.Y - a.Y) / l, Y: (b.X - a.X) / l}
			for s := 0.0; s < l; s += tt.GridM {
				c := a.Add(b.Sub(a).Mul(s / l))
				z := zs[k-1] + (zs[k]-zs[k-1])*s/l
				for _, side := range []float64{-1, 1} {
					q := c.Add(nrm.Mul(side * hw))
					tz, ok := t.at(q)
					// The surface of a crossing or parallel road owns this point, and so does a
					// road at another height closer than one grid diagonal: conform gives each
					// grid node to its nearest road, so both cannot meet the terrain there.
					if !ok || ground.ownedByOther(q, i, z, plateau, tp.RoadGapMaxM) {
						continue
					}
					gapN++
					if math.Abs(tz-z) > tp.RoadGapMaxM {
						gap++
						if gap%100 == 1 && os.Getenv("CITYPACK_DEBUG") != "" {
							slog.Warn("validate: road edge off terrain", "edge", i, "name", g.Names[ed.Name], "x", int(q.X), "y", int(q.Y), "road_m", z, "terrain_m", tz, "class", ed.Class, "layers", fmt.Sprint(ed.LayerFrom, ed.LayerTo))
						}
					}
				}
			}
		}
	}
	if shortDeck > 0 {
		slog.Warn("validate: bridge samples below the full clearance (warning only)", "count", shortDeck, "water_m", tt.Bridge.ClearWaterM, "road_m", tt.Bridge.ClearRoadM)
	}
	if lowDeck > 0 {
		fail("%d bridge samples are less than %.1f m above water or a road", lowDeck, tp.BridgeMinClearM)
	}
	slog.Info("validate: road edge vs terrain", "samples", gapN, "over_m", tp.RoadGapMaxM, "count", gap)
	if gapN > 0 && float64(gap) > tp.RoadGapShare*float64(gapN) {
		fail("%d of %d road edge samples are more than %.1f m from the terrain (limit %.1f %%)", gap, gapN, tp.RoadGapMaxM, 100*tp.RoadGapShare)
	}
	ci := newConformIndex(p, e.C.Tuning.SidewalkWidthM, tt.GridM*math.Sqrt2)
	e.validateWaterTerrain(p, t, water, ci, fail)
	e.validateDecks(p, fail)
	e.validateRoadStrips(p, t, water, ground, ci, fail)
	slog.Info("validate: terrain", "z0", m.Z0M, "exaggeration", m.Exaggeration, "stairs", stairs, "lods", len(m.Lods))
}

// validateNature checks trees, water names and prints the FL0 counts.
func (e *Env) validateNature(p *PackData, fail func(string, ...any)) {
	micro := 0
	for _, ed := range p.Graph.Edges {
		if ed.MicroOnly {
			micro++
		}
	}
	gaps := map[string]int{}
	if _, err := os.Stat(e.W("flow_gaps.json")); err == nil {
		_ = readJSON(e.W("flow_gaps.json"), &gaps)
	}
	slog.Info("validate: flow", "closed_gaps", gaps["closed_gaps"], "micro_only_alleys", micro)
	if p.Manifest.NatureVersion == 0 {
		slog.Info("validate: no nature data")
		return
	}
	nt := e.C.Tuning.Nature
	cm := float64(p.Manifest.ChunkM)
	water := newMeshIndex(p, func(m *pb.Mesh) bool { return m.Kind == pb.GroundKind_WATER })
	ground := groundSegments(p, e.C.Tuning.SidewalkWidthM, nil, 0)
	blds := newBuildingIndex(p)
	total, over, onRoad, inBld, inWater := 0, 0, 0, 0, 0
	for _, c := range p.Chunks {
		if len(c.Trees)%3 != 0 {
			fail("chunk %d_%d: trees length %d is not a multiple of 3", c.X, c.Y, len(c.Trees))
			continue
		}
		n := len(c.Trees) / 3
		total += n
		if n > nt.TreesPerChunkMax {
			over++
		}
		for i := 0; i < n; i++ {
			q := geo.Pt{X: float64(c.X)*cm + float64(c.Trees[3*i]), Y: float64(c.Y)*cm + float64(c.Trees[3*i+1])}
			if c.Trees[3*i+2]&3 > 2 {
				fail("chunk %d_%d: tree %d has size %d", c.X, c.Y, i, c.Trees[3*i+2]&3)
			}
			for _, s := range ground.near(q) {
				if qq, _ := geo.ClosestOnSegment(q, s.a, s.b); qq.Dist(q) < s.hc {
					onRoad++
					break
				}
			}
			if blds.contains(q) {
				inBld++
			}
			if _, ok := water.at(q); ok {
				inWater++
			}
		}
	}
	if over > 0 {
		fail("%d chunks hold more than %d trees", over, nt.TreesPerChunkMax)
	}
	if onRoad+inBld+inWater > 0 {
		fail("trees on a carriageway %d, in a building %d, in water %d", onRoad, inBld, inWater)
	}
	// Water bodies over named_water_ha have a name: unnamed pieces that share a vertex (a chunk
	// boundary) form one body.
	type piece struct {
		area float64
		key  []int64
	}
	var unnamed []piece
	classes := map[pb.WaterClass]int{}
	for _, c := range p.Chunks {
		for _, m := range c.Ground {
			if m.Kind != pb.GroundKind_WATER {
				continue
			}
			classes[m.WaterClass]++
			if m.Name != "" {
				continue
			}
			pc := piece{area: meshArea(m)}
			for i := 0; i+1 < len(m.Vertices); i += 2 {
				pc.key = append(pc.key, int64(m.Vertices[i])<<32|int64(uint32(m.Vertices[i+1])))
			}
			unnamed = append(unnamed, pc)
		}
	}
	parent := make([]int, len(unnamed))
	for i := range parent {
		parent[i] = i
	}
	var find func(int) int
	find = func(x int) int {
		for parent[x] != x {
			parent[x] = parent[parent[x]]
			x = parent[x]
		}
		return x
	}
	seen := map[int64]int{}
	for i, pc := range unnamed {
		for _, k := range pc.key {
			if j, ok := seen[k]; ok {
				parent[find(i)] = find(j)
			} else {
				seen[k] = i
			}
		}
	}
	area := map[int]float64{}
	for i, pc := range unnamed {
		area[find(i)] += pc.area
	}
	big := 0
	for _, a := range area {
		if a > e.C.Tuning.Nature.Pipeline.NamedWaterHa*1e4 {
			big++
		}
	}
	if big > 0 {
		fail("%d water bodies over %.0f ha have no name", big, e.C.Tuning.Nature.Pipeline.NamedWaterHa)
	}
	labels := 0
	for _, c := range p.Chunks {
		labels += len(c.Labels)
	}
	slog.Info("validate: nature", "trees", total, "labels", labels, "water_pieces", classes)
}

func meshArea(m *pb.Mesh) float64 {
	a := 0.0
	v := m.Vertices
	for t := 0; t+2 < len(m.Indices); t += 3 {
		i, j, k := m.Indices[t], m.Indices[t+1], m.Indices[t+2]
		ax, ay := float64(v[2*i])/10, float64(v[2*i+1])/10
		bx, by := float64(v[2*j])/10, float64(v[2*j+1])/10
		cx, cy := float64(v[2*k])/10, float64(v[2*k+1])/10
		a += math.Abs((bx-ax)*(cy-ay)-(cx-ax)*(by-ay)) / 2
	}
	return a
}

// meshIndex finds the mesh (triangle) under a point.
type meshIndex struct {
	tris []meshTri
	grid map[[2]int][]int
}

type meshTri struct {
	a, b, c geo.Pt
	m       *pb.Mesh
}

func newMeshIndex(p *PackData, keep func(*pb.Mesh) bool) *meshIndex {
	mi := &meshIndex{grid: map[[2]int][]int{}}
	for _, c := range p.Chunks {
		for _, m := range c.Ground {
			if !keep(m) {
				continue
			}
			v := m.Vertices
			pt := func(i uint32) geo.Pt { return geo.Pt{X: float64(v[2*i]) / 10, Y: float64(v[2*i+1]) / 10} }
			for t := 0; t+2 < len(m.Indices); t += 3 {
				tr := meshTri{pt(m.Indices[t]), pt(m.Indices[t+1]), pt(m.Indices[t+2]), m}
				mi.tris = append(mi.tris, tr)
				k := len(mi.tris) - 1
				cellsOf(math.Min(tr.a.X, math.Min(tr.b.X, tr.c.X)), math.Min(tr.a.Y, math.Min(tr.b.Y, tr.c.Y)),
					math.Max(tr.a.X, math.Max(tr.b.X, tr.c.X)), math.Max(tr.a.Y, math.Max(tr.b.Y, tr.c.Y)),
					func(c [2]int) { mi.grid[c] = append(mi.grid[c], k) })
			}
		}
	}
	return mi
}

func (mi *meshIndex) at(p geo.Pt) (*pb.Mesh, bool) {
	for _, k := range mi.grid[cellOf(p)] {
		t := mi.tris[k]
		d1 := t.b.Sub(t.a).Cross(p.Sub(t.a))
		d2 := t.c.Sub(t.b).Cross(p.Sub(t.b))
		d3 := t.a.Sub(t.c).Cross(p.Sub(t.c))
		neg := d1 < 0 || d2 < 0 || d3 < 0
		pos := d1 > 0 || d2 > 0 || d3 > 0
		if !(neg && pos) {
			return t.m, true
		}
	}
	return nil, false
}

// groundSegs indexes ground-level road segments with their heights.
type groundSeg struct {
	a, b   geo.Pt
	za, zb float64
	hw, hc float64
	edge   int
	// surface: a piece of a tunnel or bridge edge that lies on the terrain (a portal ramp);
	// conform treats it as ground, so it only counts as a neighbour in ownedByOther.
	surface bool
}

type groundSegs struct {
	segs []groundSeg
	grid map[[2]int][]int
}

// groundSegments indexes the ground roads; with terrain set it adds the tunnel and bridge segments
// whose both ends lie within tol of it (marked surface).
func groundSegments(p *PackData, sidewalkM float64, terrain func(geo.Pt) (float64, bool), tol float64) *groundSegs {
	gs := &groundSegs{grid: map[[2]int][]int{}}
	onTerrain := func(q geo.Pt, z float64) bool {
		tz, ok := terrain(q)
		return ok && math.Abs(tz-z) <= tol
	}
	for i, ed := range p.Graph.Edges {
		pts := EdgePts(ed)
		zs := edgeZ(ed)
		surface := !groundEdge(ed)
		if surface && (terrain == nil || len(zs) != len(pts)) {
			continue
		}
		hw := float64(ed.WidthM) / 2
		hc := hw // the carriageway: kept roads have a sidewalk on each side, alleys none
		if ed.Kept {
			hc = hw - sidewalkM
		}
		for k := 1; k < len(pts); k++ {
			s := groundSeg{a: pts[k-1], b: pts[k], hw: hw, hc: hc, edge: i, surface: surface}
			if len(zs) == len(pts) {
				s.za, s.zb = zs[k-1], zs[k]
			}
			if surface && !(onTerrain(s.a, s.za) && onTerrain(s.b, s.zb)) {
				continue
			}
			gs.segs = append(gs.segs, s)
			n := len(gs.segs) - 1
			r := hw
			cellsOf(math.Min(s.a.X, s.b.X)-r, math.Min(s.a.Y, s.b.Y)-r, math.Max(s.a.X, s.b.X)+r, math.Max(s.a.Y, s.b.Y)+r,
				func(c [2]int) { gs.grid[c] = append(gs.grid[c], n) })
		}
	}
	return gs
}

// groundEdge: the edge lies on the terrain as conform sees it (elevation.go profileLayer: a road
// below ground that is not a tunnel follows the bare earth).
func groundEdge(ed *pb.Edge) bool {
	return !ed.Tunnel && !ed.Bridge && profileLayer(ed, ed.LayerFrom) == 0 && profileLayer(ed, ed.LayerTo) == 0
}

func sharesNode(a, b *pb.Edge) bool {
	return a.From == b.From || a.From == b.To || a.To == b.From || a.To == b.To
}

// ownedByOther reports whether p lies in the corridor of another ground road, or within
// hw+plateau of another ground road whose height there differs from z by more than tol.
func (gs *groundSegs) ownedByOther(p geo.Pt, edge int, z, plateau, tol float64) bool {
	c := cellOf(p)
	for dx := -1; dx <= 1; dx++ {
		for dy := -1; dy <= 1; dy++ {
			for _, k := range gs.grid[[2]int{c[0] + dx, c[1] + dy}] {
				s := gs.segs[k]
				if s.edge == edge {
					continue
				}
				q, t := geo.ClosestOnSegment(p, s.a, s.b)
				d := q.Dist(p)
				if d < s.hw+0.5 || (d < s.hw+plateau && math.Abs(s.za+(s.zb-s.za)*t-z) > tol) {
					return true
				}
			}
		}
	}
	return false
}

func (gs *groundSegs) near(p geo.Pt) []groundSeg {
	var out []groundSeg
	for _, k := range gs.grid[cellOf(p)] {
		if gs.segs[k].surface {
			continue
		}
		out = append(out, gs.segs[k])
	}
	return out
}

// buildingIndex answers point-in-building for colliding buildings.
type buildingIndex struct {
	rings [][][]geo.Pt
	grid  map[[2]int][]int
}

func newBuildingIndex(p *PackData) *buildingIndex {
	bi := &buildingIndex{grid: map[[2]int][]int{}}
	for _, c := range p.Chunks {
		for _, b := range c.Buildings {
			if !b.Collide {
				continue
			}
			var rs [][]geo.Pt
			s := 0
			for _, end := range b.RingEnds {
				var r []geo.Pt
				for i := s; i < int(end); i++ {
					r = append(r, geo.Pt{X: float64(b.Rings[2*i]) / 10, Y: float64(b.Rings[2*i+1]) / 10})
				}
				rs = append(rs, r)
				s = int(end)
			}
			bi.rings = append(bi.rings, rs)
			k := len(bi.rings) - 1
			minX, minY, maxX, maxY := bounds(rs[0])
			cellsOf(minX, minY, maxX, maxY, func(c [2]int) { bi.grid[c] = append(bi.grid[c], k) })
		}
	}
	return bi
}

func (bi *buildingIndex) contains(p geo.Pt) bool {
	for _, k := range bi.grid[cellOf(p)] {
		r := bi.rings[k]
		if geo.PointInRing(p, r[0]) && !inAnyRing(p, r[1:]) {
			return true
		}
	}
	return false
}
