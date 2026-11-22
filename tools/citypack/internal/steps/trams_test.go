package steps

import (
	"testing"

	"citypack/internal/geo"
)

func TestPruneSpursKeepsLoopsAndBorderLines(t *testing.T) {
	pts := []geo.Pt{{X: 0, Y: 0}, {X: 500, Y: 0}, {X: 500, Y: 500}, {X: 0, Y: 500}, {X: 550, Y: 0}, {X: 0, Y: 900}}
	g := &workGraph{
		nodes:  pts,
		border: []bool{false, false, false, false, false, true},
		edges: []workEdge{
			seg(0, 1, pts, 0, false), seg(1, 2, pts, 0, false), seg(2, 3, pts, 0, false), seg(3, 0, pts, 0, false), // loop
			seg(1, 4, pts, 0, false), // 50 m siding: dropped
			seg(3, 5, pts, 0, false), // 400 m line out of the area: kept
		},
	}
	g = pruneSpurs(g, 120)
	if len(g.edges) != 5 {
		t.Fatalf("edges %d, want 5", len(g.edges))
	}
}

func TestTramStopsAlongChains(t *testing.T) {
	// A 1200 m chain split at a plain joint (node 1, two edges): stops at 225, 675 and 1125 m of
	// the chain; the third lands 125 m into the second edge, which runs backwards.
	pts := []geo.Pt{{X: 0, Y: 0}, {X: 1000, Y: 0}, {X: 1200, Y: 0}}
	g := &workGraph{nodes: pts, border: make([]bool, 3), edges: []workEdge{seg(0, 1, pts, 0, false), seg(2, 1, pts, 0, false)}}
	tg := tramProto(g, 450, 300)
	if len(tg.Stops) != 3 || tg.Stops[0].SM != 225 || tg.Stops[1].SM != 675 || tg.Stops[0].Edge != 0 ||
		tg.Stops[2].Edge != 1 || tg.Stops[2].SM != 75 {
		t.Fatalf("stops %v", tg.Stops)
	}
	if len(tg.Nodes) != 3 || len(tg.Edges) != 2 {
		t.Fatalf("graph %d nodes %d edges", len(tg.Nodes), len(tg.Edges))
	}
}
