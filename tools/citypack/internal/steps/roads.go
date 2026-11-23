package steps

import (
	"bufio"
	"container/heap"
	"encoding/json"
	"fmt"
	"log/slog"
	"math"
	"os"
	"slices"

	"citypack/internal/config"
	"citypack/internal/duck"
	"citypack/internal/geo"
	"citypack/internal/pb"

	"google.golang.org/protobuf/proto"
)

// Road classes that form the drivable graph; everything else (footways, steps, rail) is ignored.
var drivableClasses = map[string]pb.RoadClass{
	"motorway":      pb.RoadClass_MOTORWAY,
	"trunk":         pb.RoadClass_TRUNK,
	"primary":       pb.RoadClass_PRIMARY,
	"secondary":     pb.RoadClass_SECONDARY,
	"tertiary":      pb.RoadClass_TERTIARY,
	"residential":   pb.RoadClass_RESIDENTIAL,
	"unclassified":  pb.RoadClass_RESIDENTIAL,
	"living_street": pb.RoadClass_RESIDENTIAL,
	"service":       pb.RoadClass_SERVICE,
}

type rangeVal struct {
	Between []float64 `json:"between"`
}

func (r rangeVal) covers(t float64) bool {
	return len(r.Between) != 2 || (t >= r.Between[0] && t <= r.Between[1])
}

type accessWhen struct {
	Heading    *string  `json:"heading"`
	During     *string  `json:"during"`
	Using      []string `json:"using"`
	Recognized []string `json:"recognized"`
	Mode       []string `json:"mode"`
	Vehicle    any      `json:"vehicle"`
}

type accessRule struct {
	rangeVal
	Type string      `json:"access_type"`
	When *accessWhen `json:"when"`
}

type rawSegment struct {
	ID         string `json:"id"`
	Class      string `json:"class"`
	Subclass   string `json:"subclass"`
	Name       string `json:"name"`
	Connectors []struct {
		ID string  `json:"connector_id"`
		At float64 `json:"at"`
	} `json:"connectors"`
	Flags []struct {
		rangeVal
		Values []string `json:"values"`
	} `json:"road_flags"`
	Levels []struct {
		rangeVal
		Value int `json:"value"`
	} `json:"level_rules"`
	Access []accessRule `json:"access_restrictions"`
	Geom   struct {
		Coordinates [][2]float64 `json:"coordinates"`
	} `json:"geom"`
}

func (s *rawSegment) flag(name string, t float64) bool {
	for _, f := range s.Flags {
		if f.covers(t) && slices.Contains(f.Values, name) {
			return true
		}
	}
	return false
}

func (s *rawSegment) level(t float64) int {
	l := 0
	for _, r := range s.Levels {
		if r.covers(t) {
			l = r.Value
		}
	}
	if l == 0 {
		if s.flag("is_bridge", t) {
			l = 1
		} else if s.flag("is_tunnel", t) {
			l = -1
		}
	}
	return sign(l)
}

// oneway: 1 = only forward along the geometry, -1 = only backward, 0 = both.
// Only unconditional heading restrictions count (no mode, time or purpose).
func (s *rawSegment) oneway() int {
	for _, a := range s.Access {
		if a.Type != "denied" || a.When == nil || a.When.Heading == nil || len(a.Between) == 2 {
			continue
		}
		w := a.When
		if w.During != nil || len(w.Using) > 0 || len(w.Recognized) > 0 || len(w.Mode) > 0 || w.Vehicle != nil {
			continue
		}
		switch *w.Heading {
		case "backward":
			return 1
		case "forward":
			return -1
		}
	}
	return 0
}

func sign(v int) int {
	switch {
	case v > 0:
		return 1
	case v < 0:
		return -1
	}
	return 0
}

// workEdge is an edge while the graph is being built (metres).
type workEdge struct {
	from, to       int
	pts            []geo.Pt
	class          pb.RoadClass
	name           string
	oneway         int
	lf, lt         int
	bridge, tunnel bool
	kept           bool
	link           bool
}

type workGraph struct {
	nodes  []geo.Pt
	border []bool
	edges  []workEdge
}

// Roads builds graph.pb (uncompressed, in the work dir) from raw segments and connectors.
func Roads(e *Env) error {
	out := e.W("graph.pb")
	if e.fresh(out) {
		skip("roads", out)
		return nil
	}
	for _, c := range drivableClasses {
		if _, ok := e.C.Tuning.Roads.LanesByClass[lower(pb.RoadClass_name[int32(c)])]; !ok {
			return fmt.Errorf("tuning.yaml: roads.lanes_by_class.%s missing", lower(pb.RoadClass_name[int32(c)]))
		}
	}
	segs, err := e.loadSegments()
	if err != nil {
		return err
	}
	g := e.buildGraph(segs)
	slog.Info("roads: raw graph", "segments", len(segs), "nodes", len(g.nodes), "edges", len(g.edges))
	g = clipToArea(g, e.AreaRingM())
	g = pruneDanglingStructures(g)
	g = largestComponent(g)
	e.markKept(g)
	connectKept(g)
	connectKeptDirected(g)
	gp := e.toProto(g)
	kept := 0
	for _, ed := range gp.Edges {
		if ed.Kept {
			kept++
		}
	}
	slog.Info("roads: graph", "nodes", len(gp.Nodes), "edges", len(gp.Edges), "kept", kept, "names", len(gp.Names))
	b, err := proto.Marshal(gp)
	if err != nil {
		return err
	}
	return os.WriteFile(out, b, 0o644)
}

func (e *Env) loadSegments() ([]rawSegment, error) {
	classes := ""
	for c := range drivableClasses {
		if classes != "" {
			classes += ","
		}
		classes += duck.Quote(c)
	}
	return e.exportSegments("roads export", e.W("segments.jsonl"), "road_flags", fmt.Sprintf(
		"subtype = 'road' AND class IN (%s) AND coalesce(subclass, '') NOT IN ('driveway', 'parking_aisle')", classes))
}

// exportSegments reads Overture segments matching where (near the area) into rawSegments via tmp;
// flags is the flag column (road_flags for roads, rail_flags for rail), read as road_flags.
func (e *Env) exportSegments(label, tmp, flags, where string) ([]rawSegment, error) {
	sql := fmt.Sprintf(`COPY (
  SELECT id, class, subclass, %s AS name, connectors, %s AS road_flags, level_rules, access_restrictions,
         ST_AsGeoJSON(%s)::JSON AS geom
  FROM read_parquet(%s)
  WHERE %s
    AND ST_Intersects(geometry, ST_Buffer(ST_GeomFromText(%s), 0.003))
) TO %s (FORMAT json);`, e.C.City.NameSQL(), flags, e.projSQL("geometry"), duck.Quote(e.Raw("segment")), where, duck.Quote(e.C.City.AreaWKT()), duck.Quote(tmp))
	if _, err := duck.Exec(label, sql); err != nil {
		return nil, err
	}
	f, err := os.Open(tmp)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var segs []rawSegment
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<26)
	for sc.Scan() {
		var s rawSegment
		if err := json.Unmarshal(sc.Bytes(), &s); err != nil {
			return nil, fmt.Errorf("%s: %w", tmp, err)
		}
		if len(s.Geom.Coordinates) >= 2 {
			segs = append(segs, s)
		}
	}
	return segs, sc.Err()
}

// buildGraph splits every segment at its connectors; connectors become nodes.
func (e *Env) buildGraph(segs []rawSegment) *workGraph {
	g := &workGraph{}
	nodeOf := map[string]int{}
	node := func(id string, p geo.Pt) int {
		if n, ok := nodeOf[id]; ok {
			return n
		}
		g.nodes = append(g.nodes, p)
		g.border = append(g.border, false)
		nodeOf[id] = len(g.nodes) - 1
		return len(g.nodes) - 1
	}
	for i := range segs {
		s := &segs[i]
		pts := make([]geo.Pt, len(s.Geom.Coordinates))
		for j, c := range s.Geom.Coordinates {
			pts[j] = geo.Pt{X: c[0], Y: c[1]}
		}
		cum := make([]float64, len(pts))
		for j := 1; j < len(pts); j++ {
			cum[j] = cum[j-1] + pts[j].Dist(pts[j-1])
		}
		total := cum[len(cum)-1]
		if total < 0.5 || len(s.Connectors) < 2 {
			continue
		}
		cons := slices.Clone(s.Connectors)
		slices.SortFunc(cons, func(a, b struct {
			ID string  `json:"connector_id"`
			At float64 `json:"at"`
		}) int {
			return cmpF(a.At, b.At)
		})
		class := drivableClasses[s.Class]
		ow := s.oneway()
		for k := 0; k+1 < len(cons); k++ {
			a, b := cons[k], cons[k+1]
			piece := slicePolyline(pts, cum, a.At*total, b.At*total)
			if geo.PolylineLength(piece) < 0.1 {
				continue
			}
			mid := (a.At + b.At) / 2
			ed := workEdge{
				from:   node(a.ID, piece[0]),
				to:     node(b.ID, piece[len(piece)-1]),
				pts:    piece,
				class:  class,
				name:   s.Name,
				oneway: ow,
				lf:     s.level(a.At + 1e-6),
				lt:     s.level(b.At - 1e-6),
				bridge: s.flag("is_bridge", mid),
				tunnel: s.flag("is_tunnel", mid),
				link:   s.flag("is_link", mid) || s.Subclass == "link",
			}
			if ed.from == ed.to {
				continue
			}
			g.edges = append(g.edges, ed)
		}
	}
	return g
}

func cmpF(a, b float64) int {
	switch {
	case a < b:
		return -1
	case a > b:
		return 1
	}
	return 0
}

// slicePolyline returns the part of pts between arc lengths d0 and d1.
func slicePolyline(pts []geo.Pt, cum []float64, d0, d1 float64) []geo.Pt {
	at := func(d float64) geo.Pt {
		for j := 1; j < len(pts); j++ {
			if d <= cum[j] || j == len(pts)-1 {
				seg := cum[j] - cum[j-1]
				if seg <= 0 {
					return pts[j]
				}
				t := math.Max(0, math.Min(1, (d-cum[j-1])/seg))
				return pts[j-1].Add(pts[j].Sub(pts[j-1]).Mul(t))
			}
		}
		return pts[len(pts)-1]
	}
	out := []geo.Pt{at(d0)}
	for j := range pts {
		if cum[j] > d0 && cum[j] < d1 {
			out = append(out, pts[j])
		}
	}
	return append(out, at(d1))
}

// clipToArea drops edges outside the playable area and cuts edges crossing its border;
// the cut end becomes a border node (roadblock).
func clipToArea(g *workGraph, area []geo.Pt) *workGraph {
	in := func(p geo.Pt) bool { return geo.PointInRing(p, area) }
	out := &workGraph{nodes: g.nodes, border: g.border}
	for _, ed := range g.edges {
		a, b := in(ed.pts[0]), in(ed.pts[len(ed.pts)-1])
		switch {
		case a && b:
			out.edges = append(out.edges, ed)
		case a != b:
			pts := ed.pts
			if !a {
				pts = reversed(pts)
			}
			cut, ok := cutAtBorder(pts, area)
			if !ok {
				continue
			}
			out.nodes = append(out.nodes, cut[len(cut)-1])
			out.border = append(out.border, true)
			bn := len(out.nodes) - 1
			if a {
				ed.pts, ed.to = cut, bn
			} else {
				ed.pts, ed.from = reversed(cut), bn
			}
			out.edges = append(out.edges, ed)
		}
	}
	return out
}

// cutAtBorder keeps pts from the start (inside) up to the first border crossing.
func cutAtBorder(pts, area []geo.Pt) ([]geo.Pt, bool) {
	out := []geo.Pt{pts[0]}
	for i := 1; i < len(pts); i++ {
		best := 2.0
		for j, k := 0, len(area)-1; j < len(area); k, j = j, j+1 {
			if t, ok := geo.SegmentIntersect(pts[i-1], pts[i], area[k], area[j]); ok && t < best {
				best = t
			}
		}
		if best <= 1 {
			p := pts[i-1].Add(pts[i].Sub(pts[i-1]).Mul(best))
			if p.Dist(out[len(out)-1]) > 0.1 {
				out = append(out, p)
			}
			return out, len(out) >= 2
		}
		out = append(out, pts[i])
	}
	return nil, false
}

func reversed(p []geo.Pt) []geo.Pt {
	r := slices.Clone(p)
	slices.Reverse(r)
	return r
}

// pruneDanglingStructures removes bridge and tunnel edges that dead-end inside the area
// (data fragments such as pier ramps); a car could only drive off their end.
func pruneDanglingStructures(g *workGraph) *workGraph {
	for {
		deg := make([]int, len(g.nodes))
		for _, ed := range g.edges {
			deg[ed.from]++
			deg[ed.to]++
		}
		keep := g.edges[:0:0]
		removed := 0
		for _, ed := range g.edges {
			if (ed.bridge || ed.tunnel) &&
				((deg[ed.from] < 2 && !g.border[ed.from]) || (deg[ed.to] < 2 && !g.border[ed.to])) {
				removed++
				continue
			}
			keep = append(keep, ed)
		}
		g.edges = keep
		if removed == 0 {
			return g
		}
		slog.Info("roads: pruned dangling bridge/tunnel edges", "edges", removed)
	}
}

// largestComponent keeps the biggest undirected component and renumbers nodes.
func largestComponent(g *workGraph) *workGraph {
	comp := components(len(g.nodes), g.edges, func(workEdge) bool { return true })
	size := map[int]int{}
	for _, ed := range g.edges {
		size[comp[ed.from]]++
	}
	best, bestN := -1, 0
	for c, n := range size {
		if n > bestN {
			best, bestN = c, n
		}
	}
	remap := map[int]int{}
	out := &workGraph{}
	nodeID := func(n int) int {
		if r, ok := remap[n]; ok {
			return r
		}
		out.nodes = append(out.nodes, g.nodes[n])
		out.border = append(out.border, g.border[n])
		remap[n] = len(out.nodes) - 1
		return remap[n]
	}
	dropped := 0
	for _, ed := range g.edges {
		if comp[ed.from] != best {
			dropped++
			continue
		}
		ed.from, ed.to = nodeID(ed.from), nodeID(ed.to)
		out.edges = append(out.edges, ed)
	}
	slog.Info("roads: largest component", "edges", len(out.edges), "dropped_edges", dropped)
	return out
}

// components labels nodes by connected component over the edges passing the filter.
func components(n int, edges []workEdge, use func(workEdge) bool) []int {
	parent := make([]int, n)
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
	for _, ed := range edges {
		if use(ed) {
			parent[find(ed.from)] = find(ed.to)
		}
	}
	out := make([]int, n)
	for i := range out {
		out[i] = find(i)
	}
	return out
}

func (e *Env) markKept(g *workGraph) {
	classes := map[string]bool{}
	for _, c := range e.C.City.RoadKeepClasses {
		classes[c] = true
	}
	names := map[string]bool{}
	for _, n := range e.C.City.RoadKeepNames {
		names[n] = true
	}
	for i := range g.edges {
		ed := &g.edges[i]
		cls := pb.RoadClass_name[int32(ed.class)]
		ed.kept = classes[lower(cls)] || names[ed.name]
	}
}

func lower(s string) string {
	b := []byte(s)
	for i, c := range b {
		if c >= 'A' && c <= 'Z' {
			b[i] = c + 32
		}
	}
	return string(b)
}

// connectKept promotes the shortest alley paths needed so all kept roads form one network.
func connectKept(g *workGraph) {
	adj := make([][]int, len(g.nodes))
	for i, ed := range g.edges {
		adj[ed.from] = append(adj[ed.from], i)
		adj[ed.to] = append(adj[ed.to], i)
	}
	promoted := 0
	for iter := 0; iter < 10000; iter++ {
		comp := components(len(g.nodes), g.edges, func(ed workEdge) bool { return ed.kept })
		size := map[int]int{}
		for _, ed := range g.edges {
			if ed.kept {
				size[comp[ed.from]]++
			}
		}
		if len(size) <= 1 {
			break
		}
		main, mainN := -1, 0
		for c, n := range size {
			if n > mainN {
				main, mainN = c, n
			}
		}
		// Smallest stray component first; route from it to the main network.
		stray, strayN := -1, math.MaxInt
		for c, n := range size {
			if c != main && n < strayN {
				stray, strayN = c, n
			}
		}
		var sources []int
		for _, ed := range g.edges {
			if ed.kept && comp[ed.from] == stray {
				sources = append(sources, ed.from, ed.to)
			}
		}
		isTarget := func(n int) bool {
			for _, ei := range adj[n] {
				if g.edges[ei].kept && comp[n] == main {
					return true
				}
			}
			return false
		}
		path := dijkstra(g, adj, sources, isTarget)
		if path == nil {
			// Unreachable stray network: demote it to alleys.
			for i := range g.edges {
				if g.edges[i].kept && comp[g.edges[i].from] == stray {
					g.edges[i].kept = false
				}
			}
			continue
		}
		for _, ei := range path {
			if !g.edges[ei].kept {
				g.edges[ei].kept = true
				promoted++
			}
		}
	}
	slog.Info("roads: connectors promoted to kept", "edges", promoted)
}

type pqItem struct {
	node int
	d    float64
}
type pq []pqItem

func (q pq) Len() int           { return len(q) }
func (q pq) Less(i, j int) bool { return q[i].d < q[j].d }
func (q pq) Swap(i, j int)      { q[i], q[j] = q[j], q[i] }
func (q *pq) Push(x any)        { *q = append(*q, x.(pqItem)) }
func (q *pq) Pop() any          { o := *q; it := o[len(o)-1]; *q = o[:len(o)-1]; return it }

// dijkstra over undirected edges; returns edge indices of the path to the first target.
func dijkstra(g *workGraph, adj [][]int, sources []int, target func(int) bool) []int {
	dist := make([]float64, len(g.nodes))
	via := make([]int, len(g.nodes))
	for i := range dist {
		dist[i] = math.Inf(1)
		via[i] = -1
	}
	q := &pq{}
	for _, s := range sources {
		dist[s] = 0
		heap.Push(q, pqItem{s, 0})
	}
	for q.Len() > 0 {
		it := heap.Pop(q).(pqItem)
		if it.d > dist[it.node] {
			continue
		}
		if target(it.node) && it.d > 0 {
			var path []int
			for n := it.node; via[n] >= 0; {
				ei := via[n]
				path = append(path, ei)
				ed := g.edges[ei]
				if ed.from == n {
					n = ed.to
				} else {
					n = ed.from
				}
			}
			return path
		}
		for _, ei := range adj[it.node] {
			ed := g.edges[ei]
			o := ed.to
			if o == it.node {
				o = ed.from
			}
			d := it.d + geo.PolylineLength(ed.pts)
			if d < dist[o] {
				dist[o], via[o] = d, ei
				heap.Push(q, pqItem{o, d})
			}
		}
	}
	return nil
}

func (e *Env) toProto(g *workGraph) *pb.Graph {
	t := e.C.Tuning
	gp := &pb.Graph{Names: []string{""}}
	nameIdx := map[string]uint32{"": 0}
	for i, p := range g.nodes {
		gp.Nodes = append(gp.Nodes, &pb.Node{X: geo.DM(p.X), Y: geo.DM(p.Y), Border: g.border[i]})
	}
	for _, ed := range g.edges {
		lanes := edgeLanes(ed, t)
		width := float64(lanes)*t.LaneWidthM + 2*t.SidewalkWidthM
		if !ed.kept {
			width = t.Roads.AlleyWidthLanes * t.LaneWidthM
		}
		ni, ok := nameIdx[ed.name]
		if !ok {
			ni = uint32(len(gp.Names))
			gp.Names = append(gp.Names, ed.name)
			nameIdx[ed.name] = ni
		}
		pts := make([]int32, 0, 2*len(ed.pts))
		for _, p := range ed.pts {
			pts = append(pts, geo.DM(p.X), geo.DM(p.Y))
		}
		gp.Edges = append(gp.Edges, &pb.Edge{
			From: uint32(ed.from), To: uint32(ed.to), Points: pts,
			Class: ed.class, Name: ni, Lanes: uint32(lanes), Oneway: int32(ed.oneway),
			LayerFrom: int32(ed.lf), LayerTo: int32(ed.lt),
			Bridge: ed.bridge, Tunnel: ed.tunnel, Kept: ed.kept, WidthM: float32(width),
		})
	}
	return gp
}

// edgeLanes is the total lane count. Overture dropped `lanes` from the schema (still absent
// in 2026-11-18.0), so it comes from roads.lanes_by_class in tuning.yaml.
func edgeLanes(ed workEdge, t config.Tuning) int {
	r := t.Roads
	lanes := r.LanesByClass[lower(pb.RoadClass_name[int32(ed.class)])]
	if ed.link {
		lanes = r.LinkLanes
	}
	if ed.kept && ed.oneway != 0 {
		lanes -= r.OnewayLaneReduction
	}
	if ed.kept && lanes < r.MinKeptLanes {
		lanes = r.MinKeptLanes
	}
	return max(lanes, 1)
}

// LoadGraph reads the work-dir graph produced by Roads.
func (e *Env) LoadGraph() (*pb.Graph, error) {
	b, err := os.ReadFile(e.W("graph.pb"))
	if err != nil {
		return nil, fmt.Errorf("graph.pb missing, run roads first: %w", err)
	}
	g := &pb.Graph{}
	return g, proto.Unmarshal(b, g)
}

// EdgePts returns an edge polyline in metres.
func EdgePts(ed *pb.Edge) []geo.Pt {
	out := make([]geo.Pt, len(ed.Points)/2)
	for i := range out {
		out[i] = geo.Pt{X: float64(ed.Points[2*i]) / 10, Y: float64(ed.Points[2*i+1]) / 10}
	}
	return out
}
