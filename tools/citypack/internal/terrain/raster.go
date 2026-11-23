// Package terrain holds the pure algorithms of the citypack `elevation` step
// (Prompts/02-METROPOLE_TERRAIN_PLAN.md ch. 4, specs/terrain.md): road profiles, pins, grade
// clamping, conforming the terrain grid to the roads and shading. No I/O; the step glue lives in
// internal/steps/elevation.go.
package terrain

import (
	"math"

	"citypack/internal/geo"
)

// Raster is a regular grid in local metres. Sample (i, j) sits at (X0 + i·Step, Y0 + j·Step);
// row j = 0 is the southern edge (y grows north, like the pack).
type Raster struct {
	X0, Y0, Step float64
	W, H         int
	Z            []float64
}

func NewRaster(x0, y0, step float64, w, h int) *Raster {
	return &Raster{X0: x0, Y0: y0, Step: step, W: w, H: h, Z: make([]float64, w*h)}
}

func (r *Raster) At(i, j int) float64 {
	i = max(0, min(r.W-1, i))
	j = max(0, min(r.H-1, j))
	return r.Z[j*r.W+i]
}

func (r *Raster) Set(i, j int, v float64) { r.Z[j*r.W+i] = v }

// Pos is the position of sample (i, j).
func (r *Raster) Pos(i, j int) geo.Pt {
	return geo.Pt{X: r.X0 + float64(i)*r.Step, Y: r.Y0 + float64(j)*r.Step}
}

// Bilinear interpolates at a point, clamped to the border.
func (r *Raster) Bilinear(p geo.Pt) float64 {
	x := (p.X - r.X0) / r.Step
	y := (p.Y - r.Y0) / r.Step
	x0, y0 := math.Floor(x), math.Floor(y)
	fx, fy := x-x0, y-y0
	i, j := int(x0), int(y0)
	a := r.At(i, j)*(1-fx) + r.At(i+1, j)*fx
	b := r.At(i, j+1)*(1-fx) + r.At(i+1, j+1)*fx
	return a*(1-fy) + b*fy
}

// Fill replaces samples where mask is true by interpolation from the unmasked neighbourhood
// (repeated 4-neighbour averaging seeded from the nearest known ring). Used by `clean` for
// building footprints and for no-data cells of the DEM.
func (r *Raster) Fill(mask []bool) {
	known := make([]bool, len(r.Z))
	any := false
	for k := range known {
		known[k] = !mask[k]
		any = any || known[k]
	}
	if !any {
		return
	}
	// Grow known values outward one ring at a time (deterministic order).
	for {
		var next []int
		var vals []float64
		for j := 0; j < r.H; j++ {
			for i := 0; i < r.W; i++ {
				k := j*r.W + i
				if known[k] {
					continue
				}
				s, n := 0.0, 0
				for _, d := range [4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}} {
					a, b := i+d[0], j+d[1]
					if a < 0 || b < 0 || a >= r.W || b >= r.H || !known[b*r.W+a] {
						continue
					}
					s += r.Z[b*r.W+a]
					n++
				}
				if n > 0 {
					next = append(next, k)
					vals = append(vals, s/float64(n))
				}
			}
		}
		if len(next) == 0 {
			break
		}
		for x, k := range next {
			r.Z[k] = vals[x]
			known[k] = true
		}
	}
	// Relax the filled cells so the patch is smooth (Laplace), keeping known samples.
	for it := 0; it < 50; it++ {
		for j := 0; j < r.H; j++ {
			for i := 0; i < r.W; i++ {
				k := j*r.W + i
				if !mask[k] {
					continue
				}
				r.Z[k] = (r.At(i+1, j) + r.At(i-1, j) + r.At(i, j+1) + r.At(i, j-1)) / 4
			}
		}
	}
}

// Blur is a separable Gaussian with standard deviation sigma metres.
func (r *Raster) Blur(sigma float64) {
	s := sigma / r.Step
	if s <= 0 {
		return
	}
	rad := int(math.Ceil(3 * s))
	w := make([]float64, 2*rad+1)
	sum := 0.0
	for k := -rad; k <= rad; k++ {
		w[k+rad] = math.Exp(-float64(k*k) / (2 * s * s))
		sum += w[k+rad]
	}
	for k := range w {
		w[k] /= sum
	}
	tmp := make([]float64, len(r.Z))
	for j := 0; j < r.H; j++ {
		for i := 0; i < r.W; i++ {
			acc := 0.0
			for k := -rad; k <= rad; k++ {
				acc += w[k+rad] * r.At(i+k, j)
			}
			tmp[j*r.W+i] = acc
		}
	}
	for j := 0; j < r.H; j++ {
		for i := 0; i < r.W; i++ {
			acc := 0.0
			for k := -rad; k <= rad; k++ {
				jj := max(0, min(r.H-1, j+k))
				acc += w[k+rad] * tmp[jj*r.W+i]
			}
			r.Z[j*r.W+i] = acc
		}
	}
}

// Shade is the Horn hillshade of the raster as 0–255 with 128 = flat (specs/terrain.md):
// shade = 128 · v / cos(zenith), v the lit fraction, so a flat cell multiplies colour by 1.
func (r *Raster) Shade(azimuthDeg, altitudeDeg float64) []uint8 {
	zen := (90 - altitudeDeg) * math.Pi / 180
	az := math.Mod(360-azimuthDeg+90, 360) * math.Pi / 180
	out := make([]uint8, len(r.Z))
	for j := 0; j < r.H; j++ {
		for i := 0; i < r.W; i++ {
			dzdx := (r.At(i+1, j) - r.At(i-1, j)) / (2 * r.Step)
			// Row j grows north; the Horn formula wants dz along the southward image axis.
			dzdy := -(r.At(i, j+1) - r.At(i, j-1)) / (2 * r.Step)
			slope := math.Atan(math.Hypot(dzdx, dzdy))
			aspect := math.Atan2(dzdy, -dzdx)
			v := math.Cos(zen)*math.Cos(slope) + math.Sin(zen)*math.Sin(slope)*math.Cos(az-aspect)
			v = math.Max(0, v)
			out[j*r.W+i] = uint8(math.Max(0, math.Min(255, math.Round(128*v/math.Cos(zen)))))
		}
	}
	return out
}
