package terrain

import (
	"math"
	"testing"

	"citypack/internal/geo"
)

// A sloped kept road along x = 0 (strip 4 m), a river for x > 40 at level 0, natural terrain 10 m.
func conformScene(fit int) *Raster {
	out := NewRaster(-80, -80, 8, 21, 21)
	road := Road{A: geo.Pt{X: 0, Y: -80}, B: geo.Pt{X: 0, Y: 80}, ZA: 2, ZB: 18, HalfWidthM: 7, StripM: 4, Kept: true, Edge: 0}
	water := func(p geo.Pt) (float64, bool) { return 0, p.X > 40 }
	Conform(out, func(geo.Pt) float64 { return 10 }, water, []Road{road},
		ConformParams{SupportM: 8 * math.Sqrt2, BlendM: 24, UnderwaterM: 3, FitStepM: 2, FitPasses: fit})
	return out
}

func TestConformStripReadsProfile(t *testing.T) {
	out := conformScene(20)
	for y := -60.0; y <= 60; y += 1.7 {
		want := 2 + 16*(y+80)/160
		for _, x := range []float64{-4, -2, 0, 2, 4} {
			if got := out.Bilinear(geo.Pt{X: x, Y: y}); math.Abs(got-want) > 0.1 {
				t.Fatalf("terrain at (%.1f, %.1f) = %.2f, road %.2f", x, y, got, want)
			}
		}
	}
}

func TestConformWaterStaysBelowLevel(t *testing.T) {
	out := conformScene(20)
	for j := 0; j < out.H; j++ {
		for i := 0; i < out.W; i++ {
			if p := out.Pos(i, j); p.X > 40 && out.At(i, j) > -3+1e-9 {
				t.Fatalf("water node (%.0f, %.0f) at %.2f, want the floor −3", p.X, p.Y, out.At(i, j))
			}
		}
	}
}

// A kept road wins a node an alley also needs, even when the alley is nearer.
func TestConformKeptWinsSharedNode(t *testing.T) {
	out := NewRaster(-16, -16, 8, 5, 5)
	kept := Road{A: geo.Pt{X: -16, Y: -6}, B: geo.Pt{X: 16, Y: -6}, ZA: 5, ZB: 5, HalfWidthM: 3, Kept: true, Edge: 0}
	alley := Road{A: geo.Pt{X: -16, Y: 2}, B: geo.Pt{X: 16, Y: 2}, ZA: 9, ZB: 9, HalfWidthM: 2, Edge: 1}
	Conform(out, func(geo.Pt) float64 { return 0 }, func(geo.Pt) (float64, bool) { return 0, false }, []Road{alley, kept},
		ConformParams{SupportM: 8 * math.Sqrt2, BlendM: 24, UnderwaterM: 3})
	if z := out.At(2, 2); z != 5 { // node (0, 0): 2 m from the alley, 6 m from the kept road
		t.Fatalf("shared node = %.1f, want the kept road's 5", z)
	}
}
