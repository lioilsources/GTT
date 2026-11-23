package terrain

import (
	"math"

	"citypack/internal/geo"
)

// Road is one ground-level piece of road surface for conform: a segment with game heights at
// both ends and the corridor half width.
type Road struct {
	A, B       geo.Pt
	ZA, ZB     float64
	HalfWidthM float64
}

// ConformParams: plateau = band beyond the road edge that keeps the road height (one grid
// diagonal, so every corner of the cell around a road edge point carries the road height and
// bilinear sampling there reads the road), then a blend to the terrain.
type ConformParams struct {
	PlateauM    float64
	BlendM      float64
	UnderwaterM float64
}

// Conform fills out (whose samples define the grid) with game heights: terrain(p) everywhere,
// the road height on and next to ground roads, a smooth blend over BlendM, and water level −
// UnderwaterM in water away from roads (plan ch. 4 step 7). terrain and water work in game metres.
func Conform(out *Raster, terrain func(geo.Pt) float64, water func(geo.Pt) (float64, bool), roads []Road, p ConformParams) {
	n := len(out.Z)
	bestD := make([]float64, n)
	bestZ := make([]float64, n)
	for k := range bestD {
		bestD[k] = math.Inf(1)
	}
	reach := p.PlateauM + p.BlendM
	for _, r := range roads {
		ext := r.HalfWidthM + reach
		i0 := int(math.Floor((math.Min(r.A.X, r.B.X) - ext - out.X0) / out.Step))
		i1 := int(math.Ceil((math.Max(r.A.X, r.B.X) + ext - out.X0) / out.Step))
		j0 := int(math.Floor((math.Min(r.A.Y, r.B.Y) - ext - out.Y0) / out.Step))
		j1 := int(math.Ceil((math.Max(r.A.Y, r.B.Y) + ext - out.Y0) / out.Step))
		for j := max(0, j0); j <= min(out.H-1, j1); j++ {
			for i := max(0, i0); i <= min(out.W-1, i1); i++ {
				q := out.Pos(i, j)
				c, t := geo.ClosestOnSegment(q, r.A, r.B)
				d := c.Dist(q) - r.HalfWidthM
				k := j*out.W + i
				z := r.ZA + (r.ZB-r.ZA)*t
				// Ties (crossing roads) keep the higher surface so the road edge is never buried.
				if d < bestD[k]-1e-9 || (math.Abs(d-bestD[k]) <= 1e-9 && z > bestZ[k]) {
					bestD[k], bestZ[k] = d, z
				}
			}
		}
	}
	for j := 0; j < out.H; j++ {
		for i := 0; i < out.W; i++ {
			k := j*out.W + i
			q := out.Pos(i, j)
			d := bestD[k]
			if d <= p.PlateauM {
				out.Z[k] = bestZ[k]
				continue
			}
			if lvl, ok := water(q); ok {
				out.Z[k] = lvl - p.UnderwaterM
				continue
			}
			base := terrain(q)
			if d >= reach {
				out.Z[k] = base
				continue
			}
			t := (d - p.PlateauM) / p.BlendM
			t = t * t * (3 - 2*t)
			out.Z[k] = bestZ[k]*(1-t) + base*t
		}
	}
}
