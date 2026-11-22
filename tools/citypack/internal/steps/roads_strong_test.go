package steps

import (
	"testing"

	"citypack/internal/geo"
)

func seg(a, b int, pts []geo.Pt, oneway int, kept bool) workEdge {
	return workEdge{from: a, to: b, pts: []geo.Pt{pts[a], pts[b]}, oneway: oneway, kept: kept}
}

// A kept one-way into a kept street with no kept way back: the alley back must be promoted,
// the wrong-way alley must not.
func TestConnectKeptDirectedPromotesWayBack(t *testing.T) {
	pts := []geo.Pt{{X: 0, Y: 0}, {X: 10, Y: 0}, {X: 20, Y: 0}, {X: 10, Y: 10}, {X: 10, Y: -10}}
	g := &workGraph{
		nodes:  pts,
		border: make([]bool, len(pts)),
		edges: []workEdge{
			seg(0, 1, pts, 0, true),   // main two-way
			seg(1, 2, pts, 1, true),   // one-way out to the stray street
			seg(2, 3, pts, 0, true),   // stray two-way street
			seg(3, 1, pts, 1, false),  // alley back 3 → 1
			seg(1, 4, pts, -1, false), // alley 4 → 1 only, useless here
		},
	}
	connectKeptDirected(g)
	if !g.edges[3].kept {
		t.Fatal("way-back alley must be promoted")
	}
	if g.edges[4].kept {
		t.Fatal("unrelated alley must stay an alley")
	}
	comp, main := keptSCC(g, adjOf(g))
	for _, n := range []int{0, 1, 2, 3} {
		if comp[n] != main {
			t.Fatalf("node %d not in the main component", n)
		}
	}
}

// A one-way leaving the network with no way back stays as it is (no infinite loop, no promotion).
func TestConnectKeptDirectedLeavesDeadEnd(t *testing.T) {
	pts := []geo.Pt{{X: 0, Y: 0}, {X: 10, Y: 0}, {X: 20, Y: 0}}
	g := &workGraph{
		nodes:  pts,
		border: []bool{false, false, true},
		edges:  []workEdge{seg(0, 1, pts, 0, true), seg(1, 2, pts, 1, true)},
	}
	connectKeptDirected(g)
	if !g.edges[1].kept || len(g.edges) != 2 {
		t.Fatal("dead-end one-way must stay kept and untouched")
	}
}

func adjOf(g *workGraph) [][]int {
	adj := make([][]int, len(g.nodes))
	for i, ed := range g.edges {
		adj[ed.from] = append(adj[ed.from], i)
		adj[ed.to] = append(adj[ed.to], i)
	}
	return adj
}
