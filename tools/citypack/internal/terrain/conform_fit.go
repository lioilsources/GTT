package terrain

import (
	"math"

	"citypack/internal/geo"
)

// fitSample is one point on a road strip: the four corners of its grid cell with their
// bilinear weights, and the road height there.
type fitSample struct {
	k [4]int
	w [4]float64
	z float64
	r float64 // relaxation: kept roads 1, alleys alleyFitWeight
}

// alleyFitWeight: alley samples pull a shared node less than a kept road's (the car rides kept
// roads at speed).
const alleyFitWeight = 0.25

// fitRoads corrects the grid nodes under the road strips so that bilinear sampling on a strip
// reads the road profile (Kaczmarz projection over samples every FitStepM along and across).
// It uses only cells whose four nodes the sample's edge owns (conform's pick), so it removes the
// error of piecewise-linear profiles on bends and grade changes without fighting another road.
func fitRoads(out *Raster, roads []Road, owner []int, p ConformParams) {
	if p.FitPasses <= 0 || p.FitStepM <= 0 {
		return
	}
	var smp []fitSample
	for _, r := range roads {
		l := r.A.Dist(r.B)
		if l < 1e-6 {
			continue
		}
		dir := r.B.Sub(r.A).Mul(1 / l)
		nrm := geo.Pt{X: -dir.Y, Y: dir.X}
		w := r.strip()
		nAcross := int(math.Ceil(2*w/p.FitStepM)) + 1
		nAlong := int(math.Ceil(l/p.FitStepM)) + 1
		rel := alleyFitWeight
		if r.Kept {
			rel = 1
		}
		for a := 0; a < nAlong; a++ {
			s := math.Min(l, float64(a)*l/float64(max(1, nAlong-1)))
			c := r.A.Add(dir.Mul(s))
			z := r.ZA + (r.ZB-r.ZA)*s/l
			for b := 0; b < nAcross; b++ {
				f := -w + 2*w*float64(b)/float64(max(1, nAcross-1))
				q := c.Add(nrm.Mul(f))
				x := (q.X - out.X0) / out.Step
				y := (q.Y - out.Y0) / out.Step
				i, j := int(math.Floor(x)), int(math.Floor(y))
				if i < 0 || j < 0 || i+1 >= out.W || j+1 >= out.H {
					continue
				}
				fx, fy := x-float64(i), y-float64(j)
				ks := [4]int{j*out.W + i, j*out.W + i + 1, (j+1)*out.W + i, (j+1)*out.W + i + 1}
				// Only where the whole cell belongs to this edge: a node shared with another
				// road at another height cannot carry both profiles, the fit leaves it alone.
				if owner[ks[0]] != r.Edge || owner[ks[1]] != r.Edge || owner[ks[2]] != r.Edge || owner[ks[3]] != r.Edge {
					continue
				}
				smp = append(smp, fitSample{
					k: ks,
					w: [4]float64{(1 - fx) * (1 - fy), fx * (1 - fy), (1 - fx) * fy, fx * fy},
					z: z, r: rel,
				})
			}
		}
	}
	for pass := 0; pass < p.FitPasses; pass++ {
		for _, s := range smp {
			e, n2 := -s.z, 0.0
			for c := 0; c < 4; c++ {
				e += s.w[c] * out.Z[s.k[c]]
				n2 += s.w[c] * s.w[c]
			}
			if n2 == 0 {
				continue
			}
			g := s.r * e / n2
			for c := 0; c < 4; c++ {
				out.Z[s.k[c]] -= g * s.w[c]
			}
		}
	}
}
