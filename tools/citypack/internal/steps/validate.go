package steps

import (
	"errors"
	"fmt"
	"log/slog"
	"math"
	"os"
	"path/filepath"

	"citypack/internal/geo"
	"citypack/internal/pb"
)

// PackData is the decoded content of a citypack directory.
type PackData struct {
	Manifest  *pb.Manifest
	Graph     *pb.Graph
	Chunks    []*pb.Chunk
	Landmarks *pb.Landmarks
	Spots     *pb.Spots
	Trams     *pb.TramGraph // empty when the pack predates trams.pb
}

func ReadPack(dir string) (*PackData, error) {
	p := &PackData{Manifest: &pb.Manifest{}, Graph: &pb.Graph{}, Landmarks: &pb.Landmarks{}, Spots: &pb.Spots{}}
	if err := ReadPB(filepath.Join(dir, "manifest.pb"), p.Manifest); err != nil {
		return nil, err
	}
	if err := ReadPB(filepath.Join(dir, "graph.pb"), p.Graph); err != nil {
		return nil, err
	}
	if err := ReadPB(filepath.Join(dir, "landmarks.pb"), p.Landmarks); err != nil {
		return nil, err
	}
	if err := ReadPB(filepath.Join(dir, "spots.pb"), p.Spots); err != nil {
		return nil, err
	}
	p.Trams = &pb.TramGraph{}
	if _, err := os.Stat(filepath.Join(dir, "trams.pb")); err == nil {
		if err := ReadPB(filepath.Join(dir, "trams.pb"), p.Trams); err != nil {
			return nil, err
		}
	}
	for _, r := range p.Manifest.Chunks {
		c := &pb.Chunk{}
		if err := ReadPB(filepath.Join(dir, "chunks", fmt.Sprintf("%d_%d.pb", r.X, r.Y)), c); err != nil {
			return nil, err
		}
		p.Chunks = append(p.Chunks, c)
	}
	return p, nil
}

// Validate checks the packed output (METROPOLE_PLAN 5.3 step 9). Any failure is an error.
func Validate(e *Env) error {
	p, err := ReadPack(e.Out)
	if err != nil {
		return err
	}
	var errs []error
	fail := func(format string, a ...any) {
		errs = append(errs, fmt.Errorf(format, a...))
	}
	g := p.Graph
	if p.Manifest.FormatVersion != FormatVersion {
		fail("format_version %d, want %d", p.Manifest.FormatVersion, FormatVersion)
	}

	// 1. The drivable graph is one connected component.
	parent := make([]int, len(g.Nodes))
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
	deg := make([]int, len(g.Nodes))
	for _, ed := range g.Edges {
		parent[find(int(ed.From))] = find(int(ed.To))
		deg[ed.From]++
		deg[ed.To]++
	}
	roots := map[int]bool{}
	for _, ed := range g.Edges {
		roots[find(int(ed.From))] = true
	}
	if len(roots) != 1 {
		fail("graph has %d components", len(roots))
	}

	// 2. Every bridge and tunnel is attached at both ends (or leaves the area at a roadblock).
	loose := 0
	for i, ed := range g.Edges {
		if !ed.Bridge && !ed.Tunnel {
			continue
		}
		for _, n := range []uint32{ed.From, ed.To} {
			if deg[n] < 2 && !g.Nodes[n].Border {
				loose++
				if loose <= 5 {
					slog.Warn("validate: dangling bridge/tunnel end", "edge", i, "name", g.Names[ed.Name])
				}
			}
		}
	}
	if loose > 0 {
		fail("%d bridge/tunnel ends are not connected", loose)
	}

	// 3. A route exists from the start to every spot over kept roads, respecting one-ways.
	startEdge, _, _ := nearestKept(g, geo.Pt{X: float64(p.Manifest.Start.X) / 10, Y: float64(p.Manifest.Start.Y) / 10})
	if startEdge < 0 {
		fail("start is not near a kept road")
	} else {
		reach := reachable(g, startEdge)
		for _, s := range p.Spots.Items {
			ed := g.Edges[s.Edge]
			if !reach[ed.From] && !reach[ed.To] {
				fail("spot %s is unreachable from the start", s.Id)
			}
		}
	}

	// 4. No colliding building covers a ground-level road centreline.
	overlaps := buildingRoadOverlaps(p)
	if overlaps > 0 {
		fail("%d road sample points lie inside buildings", overlaps)
	}

	// 4b. No pedestrian-zone bollard line crosses a road centreline (specs/zones.md).
	if n := barrierRoadCrossings(p); n > 0 {
		fail("%d bollard lines cross a road centreline", n)
	}

	// 4c. Tram graph: valid node indices, stops inside their edge (specs/trams.md).
	for i, ed := range p.Trams.Edges {
		if int(ed.From) >= len(p.Trams.Nodes) || int(ed.To) >= len(p.Trams.Nodes) || len(ed.Points) < 4 {
			fail("tram edge %d is malformed", i)
		}
	}
	for i, st := range p.Trams.Stops {
		if int(st.Edge) >= len(p.Trams.Edges) {
			fail("tram stop %d has no edge", i)
			continue
		}
		pts := make([]geo.Pt, 0, len(p.Trams.Edges[st.Edge].Points)/2)
		for j := 0; j+1 < len(p.Trams.Edges[st.Edge].Points); j += 2 {
			pts = append(pts, geo.Pt{X: float64(p.Trams.Edges[st.Edge].Points[j]) / 10, Y: float64(p.Trams.Edges[st.Edge].Points[j+1]) / 10})
		}
		if l := geo.PolylineLength(pts); float64(st.SM) < 0 || float64(st.SM) > l+0.1 {
			fail("tram stop %d at %.1f m is outside its edge (%.1f m)", i, st.SM, l)
		}
	}

	// 5. Chunk size limit.
	maxB := uint32(e.C.City.MaxChunkKB) * 1024
	for _, r := range p.Manifest.Chunks {
		if r.Bytes > maxB {
			fail("chunk %d_%d is %d kB (limit %d kB)", r.X, r.Y, r.Bytes/1024, e.C.City.MaxChunkKB)
		}
	}

	// Landmarks: hero buildings must exist in some chunk.
	found := map[uint32]bool{}
	for _, c := range p.Chunks {
		for _, b := range c.Buildings {
			found[b.Landmark] = true
		}
	}
	for i, l := range e.C.Landmarks {
		if l.Kind == "" && l.Hero && !found[uint32(i+1)] {
			fail("hero landmark %s has no building", l.ID)
		}
	}
	if len(errs) > 0 {
		return errors.Join(errs...)
	}
	slog.Info("validate ok", "nodes", len(g.Nodes), "edges", len(g.Edges), "chunks", len(p.Chunks), "spots", len(p.Spots.Items),
		"tram_edges", len(p.Trams.Edges), "tram_stops", len(p.Trams.Stops))
	return nil
}

// reachable runs BFS along kept edges in their allowed direction from both ends of the start edge.
func reachable(g *pb.Graph, start int) []bool {
	out := make([][]uint32, len(g.Nodes))
	for _, ed := range g.Edges {
		if !ed.Kept {
			continue
		}
		if ed.Oneway >= 0 {
			out[ed.From] = append(out[ed.From], ed.To)
		}
		if ed.Oneway <= 0 {
			out[ed.To] = append(out[ed.To], ed.From)
		}
	}
	seen := make([]bool, len(g.Nodes))
	q := []uint32{g.Edges[start].From, g.Edges[start].To}
	for _, n := range q {
		seen[n] = true
	}
	for len(q) > 0 {
		n := q[0]
		q = q[1:]
		for _, m := range out[n] {
			if !seen[m] {
				seen[m] = true
				q = append(q, m)
			}
		}
	}
	return seen
}

func buildingRoadOverlaps(p *PackData) int {
	const cell = 64.0
	type poly struct {
		ring     []geo.Pt
		holes    [][]geo.Pt // courtyards: a driveway into a courtyard is not inside the building
		landmark uint32
	}
	grid := map[[2]int][]int{}
	var polys []poly
	for _, c := range p.Chunks {
		for _, b := range c.Buildings {
			if !b.Collide {
				continue
			}
			end := int(b.RingEnds[0])
			ring := make([]geo.Pt, end)
			minX, minY, maxX, maxY := math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)
			for i := 0; i < end; i++ {
				ring[i] = geo.Pt{X: float64(b.Rings[2*i]) / 10, Y: float64(b.Rings[2*i+1]) / 10}
				minX, maxX = math.Min(minX, ring[i].X), math.Max(maxX, ring[i].X)
				minY, maxY = math.Min(minY, ring[i].Y), math.Max(maxY, ring[i].Y)
			}
			var holes [][]geo.Pt
			for h := 1; h < len(b.RingEnds); h++ {
				s, e := int(b.RingEnds[h-1]), int(b.RingEnds[h])
				hole := make([]geo.Pt, 0, e-s)
				for i := s; i < e; i++ {
					hole = append(hole, geo.Pt{X: float64(b.Rings[2*i]) / 10, Y: float64(b.Rings[2*i+1]) / 10})
				}
				holes = append(holes, hole)
			}
			polys = append(polys, poly{ring, holes, b.Landmark})
			for x := int(math.Floor(minX / cell)); x <= int(math.Floor(maxX/cell)); x++ {
				for y := int(math.Floor(minY / cell)); y <= int(math.Floor(maxY/cell)); y++ {
					grid[[2]int{x, y}] = append(grid[[2]int{x, y}], len(polys)-1)
				}
			}
		}
	}
	bad := 0
	for _, ed := range p.Graph.Edges {
		if ed.Tunnel || ed.LayerFrom != 0 || ed.LayerTo != 0 {
			continue
		}
		pts := EdgePts(ed)
		for j := 1; j < len(pts); j++ {
			l := pts[j].Dist(pts[j-1])
			for s := 0.0; s < l; s += 2 {
				q := pts[j-1].Add(pts[j].Sub(pts[j-1]).Mul(s / l))
				for _, pi := range grid[[2]int{int(math.Floor(q.X / cell)), int(math.Floor(q.Y / cell))}] {
					if geo.PointInRing(q, polys[pi].ring) && !inAnyRing(q, polys[pi].holes) {
						bad++
						if bad <= 40 {
							slog.Warn("validate: road inside building", "name", p.Graph.Names[ed.Name], "x", int(q.X), "y", int(q.Y), "landmark", polys[pi].landmark)
						}
						break
					}
				}
			}
		}
	}
	return bad
}

func inAnyRing(q geo.Pt, rings [][]geo.Pt) bool {
	for _, r := range rings {
		if geo.PointInRing(q, r) {
			return true
		}
	}
	return false
}

// barrierRoadCrossings counts ground-level road segments that intersect a zone barrier.
func barrierRoadCrossings(p *PackData) int {
	const cell = 64.0
	type seg struct{ a, b geo.Pt }
	grid := map[[2]int][]seg{}
	for _, c := range p.Chunks {
		for _, br := range c.Barriers {
			for i := 2; i+1 < len(br.Points); i += 2 {
				s := seg{geo.Pt{X: float64(br.Points[i-2]) / 10, Y: float64(br.Points[i-1]) / 10}, geo.Pt{X: float64(br.Points[i]) / 10, Y: float64(br.Points[i+1]) / 10}}
				for x := int(math.Floor(math.Min(s.a.X, s.b.X) / cell)); x <= int(math.Floor(math.Max(s.a.X, s.b.X)/cell)); x++ {
					for y := int(math.Floor(math.Min(s.a.Y, s.b.Y) / cell)); y <= int(math.Floor(math.Max(s.a.Y, s.b.Y)/cell)); y++ {
						grid[[2]int{x, y}] = append(grid[[2]int{x, y}], s)
					}
				}
			}
		}
	}
	if len(grid) == 0 {
		return 0
	}
	bad := 0
	for _, ed := range p.Graph.Edges {
		if ed.Tunnel || ed.LayerFrom != 0 || ed.LayerTo != 0 {
			continue
		}
		pts := EdgePts(ed)
		for j := 1; j < len(pts); j++ {
			a, b := pts[j-1], pts[j]
			hit := false
			for x := int(math.Floor(math.Min(a.X, b.X) / cell)); x <= int(math.Floor(math.Max(a.X, b.X)/cell)) && !hit; x++ {
				for y := int(math.Floor(math.Min(a.Y, b.Y) / cell)); y <= int(math.Floor(math.Max(a.Y, b.Y)/cell)) && !hit; y++ {
					for _, s := range grid[[2]int{x, y}] {
						if _, ok := geo.SegmentIntersect(a, b, s.a, s.b); ok {
							hit = true
							break
						}
					}
				}
			}
			if hit {
				bad++
				if bad <= 20 {
					slog.Warn("validate: bollards across a road", "name", p.Graph.Names[ed.Name], "x", int(a.X), "y", int(a.Y))
				}
			}
		}
	}
	return bad
}
