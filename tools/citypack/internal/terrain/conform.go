package terrain

import (
	"math"

	"citypack/internal/geo"
)

// Road is one ground-level piece of road surface for conform: a segment with game heights at
// both ends, the corridor half width and the half width of the strip the car drives on
// (StripM, 0 = the whole corridor).
type Road struct {
	A, B       geo.Pt
	ZA, ZB     float64
	HalfWidthM float64
	StripM     float64
	Kept       bool // a kept road wins the grid nodes it needs over alleys
	Edge       int  // graph edge: the fit only lets an edge correct the nodes it owns
}

func (r Road) strip() float64 {
	if r.StripM > 0 {
		return r.StripM
	}
	return r.HalfWidthM
}

// ConformParams: SupportM = band beyond the strip edge whose grid nodes carry the road height.
// One grid diagonal: every corner of every cell the strip touches carries the road height, so
// bilinear sampling anywhere on the strip reads the road profile. Then a blend to the terrain.
type ConformParams struct {
	SupportM float64
	// MarginM widens the support past the corridor (sidewalks) edge: terrain within road width
	// / 2 + MarginM reads the road height, so a street never sits in a trench (trench.margin_m).
	MarginM     float64
	BlendM      float64
	UnderwaterM float64
	// Fit: after the nodes take their road heights, samples every FitStepM along and across each
	// strip correct their cell corners FitPasses times (Kaczmarz projection), so bilinear
	// sampling follows the road profile also on bends and grade changes. 0 passes = off.
	FitStepM  float64
	FitPasses int
}

// Conform fills out (whose samples define the grid) with game heights: terrain(p) everywhere,
// the road height on the grid nodes that carry a ground road strip, a smooth blend over BlendM,
// and water level − UnderwaterM in water (plan ch. 4 step 7). terrain and water work in game
// metres.
//
// A node needed by several roads goes to a kept road before an alley (the car rides kept roads
// at speed), then to the road whose strip is nearest, then to the higher one (crossings: the
// road edge is never buried). Inside water a road raises only the nodes its strip needs (a road
// on the bank); everything else there lies at the water floor.
func Conform(out *Raster, terrain func(geo.Pt) float64, water func(geo.Pt) (float64, bool), roads []Road, p ConformParams) {
	n := len(out.Z)
	type pick struct {
		rank int // 0 kept strip support, 1 other strip support, 2 blend only
		d, z float64
		edge int
	}
	better := func(a, b pick) bool {
		if a.rank != b.rank {
			return a.rank < b.rank
		}
		if math.Abs(a.d-b.d) > 1e-9 {
			return a.d < b.d
		}
		return a.z > b.z
	}
	none := pick{rank: 3, d: math.Inf(1), edge: -1}
	best := make([]pick, n)
	for k := range best {
		best[k] = none
	}
	inWater := make([]bool, n)
	lvl := make([]float64, n)
	for k := range inWater {
		lvl[k], inWater[k] = water(out.Pos(k%out.W, k/out.W))
	}
	reach := p.SupportM + p.BlendM
	for _, r := range roads {
		ext := r.HalfWidthM + p.MarginM + reach
		i0 := int(math.Floor((math.Min(r.A.X, r.B.X) - ext - out.X0) / out.Step))
		i1 := int(math.Ceil((math.Max(r.A.X, r.B.X) + ext - out.X0) / out.Step))
		j0 := int(math.Floor((math.Min(r.A.Y, r.B.Y) - ext - out.Y0) / out.Step))
		j1 := int(math.Ceil((math.Max(r.A.Y, r.B.Y) + ext - out.Y0) / out.Step))
		for j := max(0, j0); j <= min(out.H-1, j1); j++ {
			for i := max(0, i0); i <= min(out.W-1, i1); i++ {
				q := out.Pos(i, j)
				c, t := geo.ClosestOnSegment(q, r.A, r.B)
				dist := c.Dist(q)
				ds := dist - r.strip()
				pk := pick{rank: 2, d: dist - r.HalfWidthM, z: r.ZA + (r.ZB-r.ZA)*t, edge: r.Edge}
				// The carriageway's own cells go to a kept road first; the band out to the corridor
				// edge + MarginM goes to the nearest road (an alley mouth keeps its own height).
				switch {
				case ds <= p.SupportM && r.Kept:
					pk.rank, pk.d = 0, ds
				case ds <= p.SupportM || dist-r.HalfWidthM-p.MarginM <= p.SupportM:
					pk.rank, pk.d = 1, ds
				}
				k := j*out.W + i
				if better(pk, best[k]) {
					best[k] = pk
				}
			}
		}
	}
	for k := range out.Z {
		if inWater[k] {
			if best[k].rank <= 1 {
				out.Z[k] = best[k].z
			} else {
				out.Z[k] = lvl[k] - p.UnderwaterM
			}
			continue
		}
		b := best[k]
		if b.rank <= 1 {
			out.Z[k] = b.z
			continue
		}
		base := terrain(out.Pos(k%out.W, k/out.W))
		// Blend from the support edge: d is measured from the corridor edge here.
		d := b.d - p.MarginM - p.SupportM
		if b.rank > 2 || d >= p.BlendM {
			out.Z[k] = base
			continue
		}
		t := math.Max(0, d) / p.BlendM
		t = t * t * (3 - 2*t)
		out.Z[k] = b.z*(1-t) + base*t
	}
	owner := make([]int, n)
	for k, b := range best {
		owner[k] = -1
		if b.rank <= 1 {
			owner[k] = b.edge
		}
	}
	fitRoads(out, roads, owner, p)
}
