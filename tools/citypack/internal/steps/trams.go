package steps

import (
	"log/slog"
	"math"
	"os"

	"google.golang.org/protobuf/proto"

	"citypack/internal/geo"
	"citypack/internal/pb"
)

// Trams builds trams.pb (uncompressed, in the work dir; specs/trams.md): Overture rail segments of
// class tram split at connectors and clipped to the area like roads, the largest connected
// component, short dead-end spurs (depots, sidings) removed, and stops generated along long
// ground-level edges. A city without tram tracks gets an empty graph.
func Trams(e *Env) error {
	out := e.W("trams.pb")
	if e.fresh(out) {
		skip("trams", out)
		return nil
	}
	segs, err := e.exportSegments("trams export", e.W("tram_segments.jsonl"), "rail_flags", "subtype = 'rail' AND class = 'tram'")
	if err != nil {
		return err
	}
	tg := &pb.TramGraph{}
	if len(segs) > 0 {
		g := e.buildGraph(segs)
		for i := range g.edges {
			g.edges[i].oneway = 0 // trams run both ways on every track
		}
		g = clipToArea(g, e.AreaRingM())
		g = pruneDanglingStructures(g)
		g = largestComponent(g)
		g = pruneSpurs(g, e.C.Tuning.Trams.MinTrackM)
		tg = tramProto(g, e.C.Tuning.Trams.StopSpacingM, e.C.Tuning.Trams.StopMinChainM)
	}
	slog.Info("trams: graph", "segments", len(segs), "nodes", len(tg.Nodes), "edges", len(tg.Edges), "stops", len(tg.Stops))
	b, err := proto.Marshal(tg)
	if err != nil {
		return err
	}
	return os.WriteFile(out, b, 0o644)
}

// pruneSpurs repeatedly drops dead-end edges shorter than minM whose loose end is not on the
// area border (a track that leaves the area is a real line, not a siding).
func pruneSpurs(g *workGraph, minM float64) *workGraph {
	for {
		deg := make([]int, len(g.nodes))
		for _, ed := range g.edges {
			deg[ed.from]++
			deg[ed.to]++
		}
		kept := g.edges[:0:0]
		for _, ed := range g.edges {
			loose := (deg[ed.from] == 1 && !g.border[ed.from]) || (deg[ed.to] == 1 && !g.border[ed.to])
			if loose && geo.PolylineLength(ed.pts) < minM {
				continue
			}
			kept = append(kept, ed)
		}
		if len(kept) == len(g.edges) {
			return g
		}
		g = &workGraph{nodes: g.nodes, border: g.border, edges: kept}
	}
}

// tramProto renumbers the used nodes and generates stops along chains (runs of edges joined at
// nodes with exactly two track edges, i.e. between switches): on every chain longer than
// minChainM, at spacing/2, spacing/2 + spacing, … from the chain's start, skipping positions on
// bridges, in tunnels or off ground level (specs/trams.md).
func tramProto(g *workGraph, spacing, minChainM float64) *pb.TramGraph {
	tg := &pb.TramGraph{}
	idx := make([]int, len(g.nodes))
	for i := range idx {
		idx[i] = -1
	}
	nodeID := func(n int) uint32 {
		if idx[n] < 0 {
			idx[n] = len(tg.Nodes)
			p := g.nodes[n]
			tg.Nodes = append(tg.Nodes, &pb.Node{X: geo.DM(p.X), Y: geo.DM(p.Y), Border: g.border[n]})
		}
		return uint32(idx[n])
	}
	adj := make([][]int, len(g.nodes))
	for i, ed := range g.edges {
		te := &pb.TramEdge{From: nodeID(ed.from), To: nodeID(ed.to), LayerFrom: int32(ed.lf), LayerTo: int32(ed.lt), Bridge: ed.bridge, Tunnel: ed.tunnel}
		for _, p := range ed.pts {
			te.Points = append(te.Points, geo.DM(p.X), geo.DM(p.Y))
		}
		tg.Edges = append(tg.Edges, te)
		adj[ed.from] = append(adj[ed.from], i)
		adj[ed.to] = append(adj[ed.to], i)
	}
	if spacing <= 0 {
		return tg
	}
	used := make([]bool, len(g.edges))
	// walk follows a chain from node n along edge e until a node that is not a plain joint.
	walk := func(n, e int) {
		type part struct {
			edge    int
			forward bool
			l       float64
		}
		var chain []part
		total := 0.0
		for e >= 0 && !used[e] {
			used[e] = true
			ed := g.edges[e]
			l := geo.PolylineLength(ed.pts)
			fwd := ed.from == n
			chain = append(chain, part{e, fwd, l})
			total += l
			if fwd {
				n = ed.to
			} else {
				n = ed.from
			}
			next := -1
			if len(adj[n]) == 2 && !g.border[n] {
				for _, o := range adj[n] {
					if o != e {
						next = o
					}
				}
			}
			e = next
		}
		if total <= minChainM {
			return
		}
		at, k := 0.0, 0
		for d := spacing / 2; d < total; d += spacing {
			for k < len(chain) && at+chain[k].l < d {
				at += chain[k].l
				k++
			}
			if k >= len(chain) {
				break
			}
			ed := g.edges[chain[k].edge]
			if ed.lf != 0 || ed.lt != 0 || ed.bridge || ed.tunnel {
				continue
			}
			sm := d - at
			if !chain[k].forward {
				sm = chain[k].l - sm
			}
			tg.Stops = append(tg.Stops, &pb.TramStop{Edge: uint32(chain[k].edge), SM: float32(math.Round(sm*10) / 10)})
		}
	}
	// Chains start at switches, ends and border nodes; what is left are closed loops.
	for n := range g.nodes {
		if len(adj[n]) != 2 || g.border[n] {
			for _, e := range adj[n] {
				walk(n, e)
			}
		}
	}
	for e := range g.edges {
		if !used[e] {
			walk(g.edges[e].from, e)
		}
	}
	return tg
}
