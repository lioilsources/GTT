package steps

import (
	"fmt"
	"log/slog"
	"math"

	"citypack/internal/geo"
)

// deckStepMaxM is the largest height step allowed where a bridge or ramp edge meets a node.
const deckStepMaxM = 0.05

// validateDecks checks bridges, ramps and viaducts (every non-tunnel edge off the terrain, also
// Overture bridges on layer 0): no tree in their footprint on the ground below, and a continuous
// deck: every edge end at its node's height, no jump inside an edge (two vertices at one place),
// and consecutive deck edges meet at one height.
func (e *Env) validateDecks(p *PackData, fail func(string, ...any)) {
	g := p.Graph
	ob := &obstacles{deckGrid: map[[2]int][]int{}}
	nodeStep, inner := 0.0, 0.0
	var nodeAt, innerAt string
	decks, level0 := 0, 0
	for i, ed := range g.Edges {
		if ed.Tunnel || groundEdge(ed) {
			continue
		}
		decks++
		if ed.Bridge && (ed.LayerFrom == 0 || ed.LayerTo == 0) {
			level0++
		}
		ob.addDeck(ed)
		pts, zs := EdgePts(ed), edgeZ(ed)
		if len(zs) != len(pts) || len(zs) == 0 {
			continue
		}
		for _, end := range []struct {
			n uint32
			z float64
		}{{ed.From, zs[0]}, {ed.To, zs[len(zs)-1]}} {
			if d := math.Abs(end.z - float64(g.Nodes[end.n].ZDm)/10); d > nodeStep {
				nodeStep, nodeAt = d, fmt.Sprintf("edge %d %q node %d", i, g.Names[ed.Name], end.n)
			}
		}
		for k := 1; k < len(pts); k++ {
			if pts[k].Dist(pts[k-1]) < 0.05 {
				if d := math.Abs(zs[k] - zs[k-1]); d > inner {
					inner, innerAt = d, fmt.Sprintf("edge %d %q vertex %d", i, g.Names[ed.Name], k)
				}
			}
		}
	}
	// Trees: the trunk inside a deck footprint (road width) is a hit for a car on the deck.
	cm := float64(p.Manifest.ChunkM)
	under := 0
	var underAt geo.Pt
	for _, c := range p.Chunks {
		for i := 0; i+2 < len(c.Trees); i += 3 {
			q := geo.Pt{X: float64(c.X)*cm + float64(c.Trees[i]), Y: float64(c.Y)*cm + float64(c.Trees[i+1])}
			if ob.underDeck(q, 0) {
				under++
				underAt = q
			}
		}
	}
	// Bollards: none on a kept carriageway or a deck (Čechův and Jiráskův bridgeheads).
	ds := newDriveSurfaces(g, e.C.Tuning.SidewalkWidthM)
	onRoad := 0
	var onRoadAt geo.Pt
	for _, c := range p.Chunks {
		for _, br := range c.Barriers {
			for i := 0; i+1 < len(br.Points); i += 2 {
				q := geo.Pt{X: float64(br.Points[i]) / 10, Y: float64(br.Points[i+1]) / 10}
				var nx geo.Pt
				if i+3 < len(br.Points) {
					nx = geo.Pt{X: float64(br.Points[i+2]) / 10, Y: float64(br.Points[i+3]) / 10}
				} else {
					nx = q
				}
				l := q.Dist(nx)
				for s := 0.0; s <= l; s += 0.5 {
					pt := q
					if l > 0 {
						pt = q.Add(nx.Sub(q).Mul(s / l))
					}
					if ds.inside(pt, 0.15) { // dm rounding
						onRoad++
						onRoadAt = pt
						break
					}
				}
			}
		}
	}
	slog.Info("validate: decks", "edges", decks, "bridges_with_a_layer_0_end", level0, "max_node_step_m", fmt.Sprintf("%.2f", nodeStep), "max_inner_step_m", fmt.Sprintf("%.2f", inner), "trees_under", under, "bollard_points_on_road", onRoad)
	if nodeStep > deckStepMaxM {
		fail("deck height steps %.2f m at a node (%s)", nodeStep, nodeAt)
	}
	if inner > deckStepMaxM {
		fail("deck height jumps %.2f m inside an edge (%s)", inner, innerAt)
	}
	if onRoad > 0 {
		fail("%d bollard segments stand on a kept carriageway or a deck (e.g. at %.0f, %.0f)", onRoad, onRoadAt.X, onRoadAt.Y)
	}
	if under > 0 {
		fail("%d trees stand in a bridge or ramp footprint (e.g. at %.0f, %.0f)", under, underAt.X, underAt.Y)
	}
}
