package steps

import (
	"log/slog"
	"math"

	"citypack/internal/geo"
	"citypack/internal/pb"
	"citypack/internal/terrain"
)

// flagElevated marks a ground edge as a bridge when it continues a bridge deck in the air: from
// its node shared with a bridge-flagged edge its profile runs more than aboveM over the terrain
// (the conformed grid: what the car would ride) for at least runM without touching down (NYC
// West 38th Street after deck 5535, whose nodes went to the Lincoln Tunnel approach below). Conform
// then leaves the terrain below alone and clients ride its surface. A chain of such edges is
// caught over a few rounds. It returns the number of edges flagged (in g and in the profile
// input); the caller reruns the profile so the bridge grade applies to them.
func flagElevated(g *pb.Graph, edges []terrain.Edge, res terrain.Result, natural func(geo.Pt) float64, aboveM, runM float64) int {
	if aboveM <= 0 || runM <= 0 {
		return 0
	}
	deg := make([]int, len(g.Nodes))
	for _, ed := range g.Edges {
		deg[ed.From]++
		deg[ed.To]++
	}
	n := 0
	for round := 0; round < 5; round++ {
		atDeck := make([]bool, len(g.Nodes))
		for _, ed := range g.Edges {
			if ed.Bridge && !ed.Tunnel {
				atDeck[ed.From], atDeck[ed.To] = true, true
			}
		}
		changed := 0
		for i, ed := range g.Edges {
			// A dead end stays a road: validate wants every bridge joined at both ends.
			if ed.Bridge || ed.Tunnel || ed.LayerFrom != 0 || ed.LayerTo != 0 || deg[ed.From] < 2 || deg[ed.To] < 2 {
				continue
			}
			pts, zs := res.EdgePts[i], res.EdgeZ[i]
			if len(pts) < 2 {
				continue
			}
			// airborne: how far the profile stays above the terrain from one end.
			airborne := func(rev bool) float64 {
				run := 0.0
				for k := 1; k < len(pts); k++ {
					a, b, za, zb := pts[k-1], pts[k], zs[k-1], zs[k]
					if rev {
						j := len(pts) - k
						a, b, za, zb = pts[j], pts[j-1], zs[j], zs[j-1]
					}
					l := a.Dist(b)
					for s := 0.0; s < l; s += 1 {
						q := a.Add(b.Sub(a).Mul(s / l))
						if za+(zb-za)*s/l-natural(q) <= aboveM {
							return run
						}
						run += math.Min(1, l-s)
					}
				}
				return run
			}
			best := 0.0
			if atDeck[ed.From] {
				best = airborne(false)
			}
			if atDeck[ed.To] {
				best = math.Max(best, airborne(true))
			}
			if best < runM {
				continue
			}
			ed.Bridge = true
			edges[i].Bridge = true
			changed++
			slog.Info("elevation: deck continues on an unflagged edge, flagged as bridge", "edge", i, "name", g.Names[ed.Name], "airborne_m", int(best))
		}
		n += changed
		if changed == 0 {
			break
		}
	}
	return n
}

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
