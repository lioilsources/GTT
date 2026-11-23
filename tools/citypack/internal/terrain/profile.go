package terrain

import (
	"container/heap"
	"fmt"
	"math"
	"sort"

	"citypack/internal/geo"
)

// within returns the vertices reachable from starts along links within r metres (Dijkstra).
func within(links []link, adj [][]int, starts []int, r float64) []int {
	dist := map[int]float64{}
	q := &pq{}
	for _, s := range starts {
		dist[s] = 0
		heap.Push(q, pqItem{v: s})
	}
	for q.Len() > 0 {
		it := heap.Pop(q).(pqItem)
		if it.d > dist[it.v] {
			continue
		}
		for _, k := range adj[it.v] {
			l := links[k]
			o := l.a
			if o == it.v {
				o = l.b
			}
			nd := it.d + l.l
			if old, ok := dist[o]; nd > r || (ok && old <= nd) {
				continue
			}
			dist[o] = nd
			heap.Push(q, pqItem{v: o, d: nd})
		}
	}
	out := make([]int, 0, len(dist))
	for v := range dist {
		out = append(out, v)
	}
	sort.Ints(out)
	return out
}

// Params are the terrain numbers from content/tuning.yaml `terrain` (game metres unless noted).
type Params struct {
	Exaggeration float64
	MaxGrade     map[string]float64 // motorway, trunk, primary, secondary, tertiary, alley
	ClearWaterM  float64            // bridge deck above water
	ClearRoadM   float64            // bridge deck above a crossed road
	BridgeGrade  float64
	DepthWaterM  float64 // tunnel below water level
	DepthLandM   float64 // tunnel below terrain
	TunnelGrade  float64
	StepM        float64 // profile sample spacing along edges
	WindowM      float64 // smoothing window along the route
	ElevatedM    float64 // viaduct over land: terrain + this
	GradeTolM    float64 // grade_clamp stops below this excess
	GradePasses  int
	ZTolM        float64 // inserted samples within this of the straight profile are dropped
}

// Edge is one graph edge as the profile sees it.
type Edge struct {
	From, To   int
	Pts        []geo.Pt // full polyline incl. both nodes
	Class      string   // key into Params.MaxGrade
	LayerFrom  int
	LayerTo    int
	HalfWidthM float64
	DeckM      float64 // > 0: curated deck height above water (iconic bridges), replaces ClearWaterM
	Bridge     bool    // terrain.bridge.max_grade applies
	Tunnel     bool    // terrain.tunnel.max_grade applies
}

// Input is everything the profile needs besides Params.
type Input struct {
	Nodes []geo.Pt
	Edges []Edge
	// Ground is the cleaned real elevation in metres.
	Ground func(geo.Pt) float64
	// Water reports the real water level when p lies in a water body.
	Water func(geo.Pt) (float64, bool)
	Z0    float64
}

// Game converts a real elevation to game metres (exaggerated, relative to z0).
func (in *Input) game(z float64, p Params) float64 { return (z - in.Z0) * p.Exaggeration }

// Result holds game heights (metres relative to z0) for nodes and densified edges.
type Result struct {
	NodeZ   []float64
	EdgePts [][]geo.Pt
	EdgeZ   [][]float64
	Stairs  []bool
	// Clamped counts samples grade_clamp moved by more than GradeTolM; Passes is the number of
	// passes it ran; Residual is the largest grade excess left (metres).
	Clamped  int
	Passes   int
	Residual float64
	Worst    string // the link with the residual, for the report
	Relaxed  int    // pin bounds relaxed to resolve conflicts
	// Ground marks samples on layer 0 per edge vertex (for conform).
	GroundPt [][]bool
}

type vtx struct {
	p        geo.Pt
	layer    int
	orig     bool // original polyline vertex (kept in the output)
	z        float64
	lo, hi   float64
	fixed    bool    // never moved by grade_clamp (no sample is fixed today: pins are bounds)
	portal   bool    // ground sample next to a structure
	terrainG float64 // smoothed terrain, game metres
}

type link struct {
	a, b  int
	l     float64
	grade float64
	edge  int
}

// Profile runs profile → pins → exaggerate → grade_clamp (plan ch. 4 steps 3–6).
func Profile(in Input, p Params) Result {
	var vs []vtx
	for _, n := range in.Nodes {
		vs = append(vs, vtx{p: n, orig: true, lo: math.Inf(-1), hi: math.Inf(1)})
	}
	nodeLayer := make([]map[int]bool, len(in.Nodes))
	for i := range nodeLayer {
		nodeLayer[i] = map[int]bool{}
	}
	seqs := make([][]int, len(in.Edges))
	var links []link
	for ei, e := range in.Edges {
		nodeLayer[e.From][e.LayerFrom] = true
		nodeLayer[e.To][e.LayerTo] = true
		total := geo.PolylineLength(e.Pts)
		seq := []int{e.From}
		s := 0.0
		for k := 1; k < len(e.Pts); k++ {
			a, b := e.Pts[k-1], e.Pts[k]
			l := a.Dist(b)
			n := int(math.Ceil(l / p.StepM))
			for m := 1; m <= n; m++ {
				if k == len(e.Pts)-1 && m == n {
					break
				}
				t := float64(m) / float64(n)
				q := a.Add(b.Sub(a).Mul(t))
				st := s + l*t
				// A structure edge is structure all along: its ground end is the portal (an edge
				// from ground onto a bridge rises over its whole length). Only a bridge-to-tunnel
				// edge switches halfway.
				layer := e.LayerFrom
				switch {
				case e.LayerFrom == 0:
					layer = e.LayerTo
				case e.LayerTo != 0 && total > 0 && st/total >= 0.5:
					layer = e.LayerTo
				}
				vs = append(vs, vtx{p: q, layer: layer, orig: m == n, lo: math.Inf(-1), hi: math.Inf(1)})
				seq = append(seq, len(vs)-1)
			}
			s += l
		}
		seq = append(seq, e.To)
		seqs[ei] = seq
		g := grade(p, e.Class)
		for k := 1; k < len(seq); k++ {
			links = append(links, link{a: seq[k-1], b: seq[k], l: vs[seq[k-1]].p.Dist(vs[seq[k]].p), grade: g, edge: ei})
		}
	}
	for i := range in.Nodes {
		vs[i].layer = 0
		if !nodeLayer[i][0] {
			for _, l := range []int{1, -1} {
				if nodeLayer[i][l] {
					vs[i].layer = l
				}
			}
		}
	}
	// Bridges and tunnels have their own limit; other elevated ramps keep their class limit.
	for k := range links {
		e := in.Edges[links[k].edge]
		if e.Bridge {
			links[k].grade = math.Min(links[k].grade, p.BridgeGrade)
		}
		if e.Tunnel {
			links[k].grade = math.Min(links[k].grade, p.TunnelGrade)
		}
	}
	adj := make([][]int, len(vs))
	for k, l := range links {
		adj[l.a] = append(adj[l.a], k)
		adj[l.b] = append(adj[l.b], k)
	}

	// 3. profile: raw terrain, smoothed along the route (window centred on each sample).
	raw := make([]float64, len(vs))
	for i := range vs {
		raw[i] = in.Ground(vs[i].p)
	}
	smooth := smoothAlong(vs, links, adj, raw, p.WindowM/2)
	for i := range vs {
		vs[i].terrainG = in.game(smooth[i], p)
		vs[i].z = vs[i].terrainG
	}

	// 4. pins. Structure samples get bounds (a deck at least clear_* above what it crosses, a
	// tunnel at least depth_* below), capped by what the structure's grade reaches from its
	// portals (ground samples next to it) and never below the straight span between them.
	for _, l := range links {
		a, b := &vs[l.a], &vs[l.b]
		if a.layer == 0 && b.layer != 0 {
			a.portal = true
		}
		if b.layer == 0 && a.layer != 0 {
			b.portal = true
		}
	}
	dist, portalZ, span := portalDistances(vs, links, adj)
	ground := groundIndex(vs, links, in.Edges)
	edgeOf := make([]int, len(vs))
	for i := range edgeOf {
		edgeOf[i] = -1
	}
	for _, l := range links {
		edgeOf[l.a], edgeOf[l.b] = l.edge, l.edge
	}
	for i := range vs {
		v := &vs[i]
		if v.layer == 0 {
			continue
		}
		// An upper-level edge flagged as a tunnel (ramps inside a terminal building) has no
		// deck to pin: it follows the clamp only.
		if e := edgeOf[i]; v.layer > 0 && e >= 0 && in.Edges[e].Tunnel {
			continue
		}
		level, wet := in.Water(v.p)
		if v.layer > 0 {
			var want float64
			switch {
			case wet:
				clear := p.ClearWaterM
				if e := edgeOf[i]; e >= 0 && in.Edges[e].DeckM > 0 {
					clear = in.Edges[e].DeckM
				}
				want = in.game(level, p) + clear
			default:
				if rz, ok := ground.under(v.p, vs); ok {
					want = rz + p.ClearRoadM
				} else {
					want = v.terrainG + p.ElevatedM
				}
			}
			if !math.IsInf(dist[i], 1) {
				want = math.Min(want, portalZ[i]+p.BridgeGrade*dist[i])
			}
			// A deck never sags below the straight line between its portals (valley viaducts).
			if !math.IsNaN(span[i]) {
				want = math.Max(want, span[i])
			}
			v.lo = want
			v.z = math.Max(v.z, want)
		} else {
			want := v.terrainG - p.DepthLandM
			if wet {
				want = math.Min(want, in.game(level, p)-p.DepthWaterM)
			}
			if !math.IsInf(dist[i], 1) {
				want = math.Max(want, portalZ[i]-p.TunnelGrade*dist[i])
			}
			if !math.IsNaN(span[i]) {
				want = math.Min(want, span[i])
			}
			v.hi = want
			v.z = math.Min(v.z, want)
		}
	}

	// 6. grade_clamp.
	start := make([]float64, len(vs))
	for i := range vs {
		start[i] = vs[i].z
	}
	res := Result{}
	clampPasses := func() {
		for pass := 0; pass < p.GradePasses; pass++ {
			worst := 0.0
			for _, l := range links {
				a, b := &vs[l.a], &vs[l.b]
				d := b.z - a.z
				ex := math.Abs(d) - l.grade*l.l
				if ex <= 0 {
					continue
				}
				worst = math.Max(worst, ex)
				sgn := math.Copysign(1, d) // b is higher when d > 0
				switch {
				case !a.fixed && !b.fixed:
					a.z += sgn * ex / 2
					b.z -= sgn * ex / 2
				case !a.fixed:
					a.z += sgn * ex
				case !b.fixed:
					b.z -= sgn * ex
				}
				a.z = math.Min(math.Max(a.z, a.lo), a.hi)
				b.z = math.Min(math.Max(b.z, b.lo), b.hi)
			}
			res.Passes++
			// Converge well below the tolerance so validated grades stay within max_grade.
			if worst < p.GradeTolM/10 {
				return
			}
		}
	}
	// Pins that cannot all hold (a deck meeting a tunnel, a clearance next to a steep portal)
	// give way before a road turns into stairs: a bound that blocks a link is relaxed by the
	// excess and the clamp runs again (at most relaxRounds times).
	const relaxRounds = 60
	for round := 0; ; round++ {
		clampPasses()
		if round == relaxRounds {
			break
		}
		relaxed := 0
		relax := func(v *vtx, ex float64) bool {
			done := false
			if v.z <= v.lo+1e-9 && !math.IsInf(v.lo, -1) {
				v.lo -= ex
				relaxed++
				done = true
			}
			if v.z >= v.hi-1e-9 && !math.IsInf(v.hi, 1) {
				v.hi += ex
				relaxed++
				done = true
			}
			return done
		}
		var stuck []int // violating links whose own ends hold no bound
		for k, l := range links {
			a, b := &vs[l.a], &vs[l.b]
			ex := math.Abs(b.z-a.z) - l.grade*l.l
			if ex <= p.GradeTolM {
				continue
			}
			ra, rb := relax(a, ex), relax(b, ex)
			if !ra && !rb {
				stuck = append(stuck, k)
			}
		}
		// A conflict can sit a few links away: a portal ceiling and a deck floor joined by a short
		// street (Mrázovka portal at Radlická, Prague). Relax the active bounds within the ramp a
		// structure needs, (clear_road + depth_land) / bridge grade, of such a link.
		if len(stuck) > 0 && p.BridgeGrade > 0 {
			reach := (p.ClearRoadM + p.DepthLandM) / p.BridgeGrade
			seen := map[int]float64{}
			for _, k := range stuck {
				l := links[k]
				ex := math.Abs(vs[l.b].z-vs[l.a].z) - l.grade*l.l
				for _, d := range within(links, adj, []int{l.a, l.b}, reach) {
					seen[d] = math.Max(seen[d], ex)
				}
			}
			ids := make([]int, 0, len(seen))
			for v := range seen {
				ids = append(ids, v)
			}
			sort.Ints(ids) // deterministic
			for _, v := range ids {
				relax(&vs[v], seen[v])
			}
		}
		if relaxed == 0 {
			break
		}
		res.Relaxed += relaxed
	}
	for i := range vs {
		if math.Abs(vs[i].z-start[i]) > p.GradeTolM {
			res.Clamped++
		}
	}
	res.Stairs = make([]bool, len(in.Edges))
	for _, l := range links {
		ex := math.Abs(vs[l.b].z-vs[l.a].z) - l.grade*l.l
		if ex > res.Residual {
			a, b := vs[l.a], vs[l.b]
			res.Worst = fmt.Sprintf("edge %d len %.1f grade %.2f: a (%.0f,%.0f) layer %d z %.1f [%.1f,%.1f] | b (%.0f,%.0f) layer %d z %.1f [%.1f,%.1f]",
				l.edge, l.l, l.grade, a.p.X, a.p.Y, a.layer, a.z, a.lo, a.hi, b.p.X, b.p.Y, b.layer, b.z, b.lo, b.hi)
		}
		res.Residual = math.Max(res.Residual, ex)
		if ex > p.GradeTolM {
			res.Stairs[l.edge] = true
		}
	}

	res.NodeZ = make([]float64, len(in.Nodes))
	for i := range in.Nodes {
		res.NodeZ[i] = vs[i].z
	}
	res.EdgePts = make([][]geo.Pt, len(in.Edges))
	res.EdgeZ = make([][]float64, len(in.Edges))
	res.GroundPt = make([][]bool, len(in.Edges))
	for ei, seq := range seqs {
		keep := simplifyZ(vs, seq, p.ZTolM)
		for _, k := range keep {
			res.EdgePts[ei] = append(res.EdgePts[ei], vs[k].p)
			res.EdgeZ[ei] = append(res.EdgeZ[ei], vs[k].z)
			res.GroundPt[ei] = append(res.GroundPt[ei], vs[k].layer == 0)
		}
	}
	return res
}

func grade(p Params, class string) float64 {
	if g, ok := p.MaxGrade[class]; ok {
		return g
	}
	return p.MaxGrade["alley"]
}

// smoothAlong averages raw values over all samples within radius r along the network (graph
// distance), weighting each sample by half its adjacent link lengths.
func smoothAlong(vs []vtx, links []link, adj [][]int, raw []float64, r float64) []float64 {
	w := make([]float64, len(vs))
	for _, l := range links {
		w[l.a] += l.l / 2
		w[l.b] += l.l / 2
	}
	out := make([]float64, len(vs))
	dist := map[int]float64{}
	for i := range vs {
		if r <= 0 || len(adj[i]) == 0 {
			out[i] = raw[i]
			continue
		}
		clear(dist)
		dist[i] = 0
		q := &pq{{i, 0}}
		sw, sz := 0.0, 0.0
		for q.Len() > 0 {
			it := heap.Pop(q).(pqItem)
			if it.d > dist[it.v] {
				continue
			}
			wv := math.Max(w[it.v], 1e-3)
			sw += wv
			sz += wv * raw[it.v]
			for _, k := range adj[it.v] {
				l := links[k]
				o := l.a
				if o == it.v {
					o = l.b
				}
				nd := it.d + l.l
				if nd > r {
					continue
				}
				if d, ok := dist[o]; ok && d <= nd {
					continue
				}
				dist[o] = nd
				heap.Push(q, pqItem{o, nd})
			}
		}
		out[i] = sz / sw
	}
	return out
}

// portalDistances returns, for every structure sample, the distance to its nearest portal along
// the structure, that portal's height, and the inverse-distance blend of all portal heights of
// its structure (the straight span between two portals; NaN without portals).
func portalDistances(vs []vtx, links []link, adj [][]int) ([]float64, []float64, []float64) {
	n := len(vs)
	dist := make([]float64, n)
	pz := make([]float64, n)
	sumW := make([]float64, n)
	sumZ := make([]float64, n)
	d := make([]float64, n)
	for i := range dist {
		dist[i] = math.Inf(1)
		d[i] = math.Inf(1)
	}
	var touched []int
	for src := range vs {
		if !vs[src].portal {
			continue
		}
		for _, t := range touched {
			d[t] = math.Inf(1)
		}
		touched = append(touched[:0], src)
		d[src] = 0
		q := &pq{{src, 0}}
		for q.Len() > 0 {
			it := heap.Pop(q).(pqItem)
			if it.d > d[it.v] {
				continue
			}
			if it.v != src {
				w := 1 / math.Max(it.d, 1)
				sumW[it.v] += w
				sumZ[it.v] += w * vs[src].z
				if it.d < dist[it.v] {
					dist[it.v], pz[it.v] = it.d, vs[src].z
				}
			}
			for _, k := range adj[it.v] {
				l := links[k]
				o := l.a
				if o == it.v {
					o = l.b
				}
				if vs[o].layer == 0 {
					continue
				}
				if nd := it.d + l.l; nd < d[o] {
					if math.IsInf(d[o], 1) {
						touched = append(touched, o)
					}
					d[o] = nd
					heap.Push(q, pqItem{o, nd})
				}
			}
		}
	}
	span := make([]float64, n)
	for i := range span {
		span[i] = math.NaN()
		if sumW[i] > 0 {
			span[i] = sumZ[i] / sumW[i]
		}
	}
	return dist, pz, span
}

// simplifyZ keeps original vertices and only those inserted samples needed to stay within tol
// of the linear profile between kept neighbours (Douglas–Peucker on (s, z)).
func simplifyZ(vs []vtx, seq []int, tol float64) []int {
	s := make([]float64, len(seq))
	for k := 1; k < len(seq); k++ {
		s[k] = s[k-1] + vs[seq[k-1]].p.Dist(vs[seq[k]].p)
	}
	keep := make([]bool, len(seq))
	keep[0], keep[len(seq)-1] = true, true
	for k := range seq {
		if vs[seq[k]].orig {
			keep[k] = true
		}
	}
	var dp func(a, b int)
	dp = func(a, b int) {
		worst, wk := tol, -1
		for k := a + 1; k < b; k++ {
			t := 0.0
			if s[b] > s[a] {
				t = (s[k] - s[a]) / (s[b] - s[a])
			}
			lin := vs[seq[a]].z + (vs[seq[b]].z-vs[seq[a]].z)*t
			if d := math.Abs(vs[seq[k]].z - lin); d > worst {
				worst, wk = d, k
			}
		}
		if wk >= 0 {
			keep[wk] = true
			dp(a, wk)
			dp(wk, b)
		}
	}
	// Run between consecutive kept (original) vertices, then once more over the whole edge so
	// the kept set is stable.
	prev := 0
	for k := 1; k < len(seq); k++ {
		if keep[k] {
			dp(prev, k)
			prev = k
		}
	}
	var out []int
	for k, ok := range keep {
		if ok {
			out = append(out, seq[k])
		}
	}
	return out
}

// groundIdx finds the ground road under a point (for bridge clearance over roads).
type groundIdx struct {
	cell  float64
	grid  map[[2]int][]int
	links []link
	hw    []float64
}

func groundIndex(vs []vtx, links []link, edges []Edge) *groundIdx {
	g := &groundIdx{cell: 32, grid: map[[2]int][]int{}}
	for _, l := range links {
		if vs[l.a].layer != 0 || vs[l.b].layer != 0 {
			continue
		}
		g.links = append(g.links, l)
		g.hw = append(g.hw, edges[l.edge].HalfWidthM)
		k := len(g.links) - 1
		a, b := vs[l.a].p, vs[l.b].p
		for x := int(math.Floor((math.Min(a.X, b.X) - g.hw[k]) / g.cell)); x <= int(math.Floor((math.Max(a.X, b.X)+g.hw[k])/g.cell)); x++ {
			for y := int(math.Floor((math.Min(a.Y, b.Y) - g.hw[k]) / g.cell)); y <= int(math.Floor((math.Max(a.Y, b.Y)+g.hw[k])/g.cell)); y++ {
				g.grid[[2]int{x, y}] = append(g.grid[[2]int{x, y}], k)
			}
		}
	}
	return g
}

// under returns the highest ground road surface (current z) whose corridor covers p.
func (g *groundIdx) under(p geo.Pt, vs []vtx) (float64, bool) {
	best, ok := math.Inf(-1), false
	for _, k := range g.grid[[2]int{int(math.Floor(p.X / g.cell)), int(math.Floor(p.Y / g.cell))}] {
		l := g.links[k]
		q, t := geo.ClosestOnSegment(p, vs[l.a].p, vs[l.b].p)
		if q.Dist(p) > g.hw[k] {
			continue
		}
		z := vs[l.a].z + (vs[l.b].z-vs[l.a].z)*t
		if z > best {
			best, ok = z, true
		}
	}
	return best, ok
}

type pqItem struct {
	v int
	d float64
}
type pq []pqItem

func (q pq) Len() int { return len(q) }
func (q pq) Less(i, j int) bool {
	if q[i].d != q[j].d {
		return q[i].d < q[j].d
	}
	return q[i].v < q[j].v
}
func (q pq) Swap(i, j int) { q[i], q[j] = q[j], q[i] }
func (q *pq) Push(x any)   { *q = append(*q, x.(pqItem)) }
func (q *pq) Pop() any {
	old := *q
	it := old[len(old)-1]
	*q = old[:len(old)-1]
	return it
}
