package steps

import (
	"math"

	"citypack/internal/geo"
	"citypack/internal/pb"
)

// driveSurfaces indexes where no bollard may stand: the carriageway of every kept ground road
// and the whole footprint of every bridge, ramp and viaduct (also Overture bridges on layer 0).
// The zones step only subtracts layer-0 road corridors, so a pedestrian zone at a bridgehead
// (Čechův most, Jiráskův most) used to draw its outline across the deck.
type driveSurfaces struct {
	segs []roadSeg
	grid map[[2]int][]int
}

func newDriveSurfaces(g *pb.Graph, sidewalkM float64) *driveSurfaces {
	ds := &driveSurfaces{grid: map[[2]int][]int{}}
	for _, ed := range g.Edges {
		var hw float64
		switch {
		case ed.Tunnel:
			continue
		case !groundEdge(ed):
			hw = float64(ed.WidthM) / 2
		case ed.Kept:
			hw = carriageway(ed, sidewalkM)
		default:
			continue
		}
		pts := EdgePts(ed)
		for k := 1; k < len(pts); k++ {
			s := roadSeg{a: pts[k-1], b: pts[k], hw: hw}
			ds.segs = append(ds.segs, s)
			n := len(ds.segs) - 1
			cellsOf(math.Min(s.a.X, s.b.X)-hw, math.Min(s.a.Y, s.b.Y)-hw, math.Max(s.a.X, s.b.X)+hw, math.Max(s.a.Y, s.b.Y)+hw,
				func(c [2]int) { ds.grid[c] = append(ds.grid[c], n) })
		}
	}
	return ds
}

// inside: p lies on a drive surface (more than tol inside its edge).
func (ds *driveSurfaces) inside(p geo.Pt, tol float64) bool {
	for _, k := range ds.grid[cellOf(p)] {
		s := ds.segs[k]
		if q, _ := geo.ClosestOnSegment(p, s.a, s.b); q.Dist(p) < s.hw-tol {
			return true
		}
	}
	return false
}

// clipBarriers cuts every barrier line where it runs over a drive surface and drops pieces
// shorter than minLen.
func clipBarriers(rows []BarrierRow, ds *driveSurfaces, minLen float64) []BarrierRow {
	const step = 0.25
	var out []BarrierRow
	for _, r := range rows {
		var cur []geo.Pt
		flush := func() {
			if len(cur) >= 2 && geo.PolylineLength(cur) >= minLen {
				out = append(out, BarrierRow{CX: r.CX, CY: r.CY, Pts: cur})
			}
			cur = nil
		}
		for k := 1; k < len(r.Pts); k++ {
			a, b := r.Pts[k-1], r.Pts[k]
			l := a.Dist(b)
			n := max(1, int(math.Ceil(l/step)))
			for m := 0; m <= n; m++ {
				if m == 0 && k > 1 {
					continue // shared with the previous segment
				}
				q := a.Add(b.Sub(a).Mul(float64(m) / float64(n)))
				if ds.inside(q, 0) {
					flush()
					continue
				}
				// Keep the input vertices and the cut points, not every sample.
				if m == 0 || m == n || len(cur) == 0 || ds.inside(a.Add(b.Sub(a).Mul(float64(m+1)/float64(n))), 0) {
					cur = append(cur, q)
				}
			}
		}
		flush()
	}
	return out
}
