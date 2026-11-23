package steps

import (
	"log/slog"
	"math"

	"citypack/internal/pb"
)

// carriageway is the half width a car drives on: kept roads have a sidewalk on each side,
// alleys none (validate_m5.go groundSegments uses the same rule).
func carriageway(ed *pb.Edge, sidewalkM float64) float64 {
	hw := float64(ed.WidthM) / 2
	if ed.Kept && hw-sidewalkM > 0 {
		return hw - sidewalkM
	}
	return hw
}

// flagWaterBridges marks a ground edge that runs over water for at least minRunM in one stretch
// as a bridge (layer unchanged): clients then ride its own surface (specs/terrain.md groundZ) and
// conform keeps the water below it flat. Shorter crossings (a lane over a mill race) stay ground.
// The flag goes into graph_z.pb and so into the pack.
func flagWaterBridges(g *pb.Graph, wi *waterIndex, minRunM float64) int {
	if minRunM <= 0 {
		return 0
	}
	const step = 2.0
	deg := make([]int, len(g.Nodes))
	for _, ed := range g.Edges {
		deg[ed.From]++
		deg[ed.To]++
	}
	n := 0
	for i, ed := range g.Edges {
		if ed.Bridge || ed.Tunnel || ed.LayerFrom != 0 || ed.LayerTo != 0 {
			continue
		}
		// A dead end over water is a pier road: it stays ground (validate wants bridges joined
		// at both ends), its strip keeps the nodes it needs.
		if deg[ed.From] < 2 || deg[ed.To] < 2 {
			continue
		}
		pts := EdgePts(ed)
		run, best := 0.0, 0.0
		for k := 1; k < len(pts); k++ {
			l := pts[k].Dist(pts[k-1])
			for s := 0.0; s < l; s += step {
				q := pts[k-1].Add(pts[k].Sub(pts[k-1]).Mul(s / l))
				if _, ok := wi.level(q); ok {
					run += math.Min(step, l-s)
					best = math.Max(best, run)
				} else {
					run = 0
				}
			}
		}
		if best < minRunM {
			continue
		}
		ed.Bridge = true
		n++
		slog.Info("elevation: unflagged bridge over water", "edge", i, "name", g.Names[ed.Name], "over_water_m", int(best))
	}
	return n
}
