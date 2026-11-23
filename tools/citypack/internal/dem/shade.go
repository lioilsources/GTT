package dem

import "math"

// Hillshade is the standard Horn illumination model, 0 (shadow) to 1 (lit), over a north-up grid
// (row 0 = north). Ported from terrain-fetch preview.go.
func Hillshade(g *Grid, metersPerPx, azimuthDeg, altitudeDeg float64) []float64 {
	zenith := (90 - altitudeDeg) * math.Pi / 180
	// ESRI convention: the compass azimuth becomes a math angle. terrain-fetch used the compass
	// value directly, which lit the relief from the mirrored direction.
	az := math.Mod(360-azimuthDeg+90, 360) * math.Pi / 180
	out := make([]float64, g.W*g.H)
	for y := 0; y < g.H; y++ {
		for x := 0; x < g.W; x++ {
			dzdx := float64(g.ClampedAt(x+1, y)-g.ClampedAt(x-1, y)) / (2 * metersPerPx)
			dzdy := float64(g.ClampedAt(x, y+1)-g.ClampedAt(x, y-1)) / (2 * metersPerPx)
			slope := math.Atan(math.Hypot(dzdx, dzdy))
			aspect := math.Atan2(dzdy, -dzdx)
			v := math.Cos(zenith)*math.Cos(slope) +
				math.Sin(zenith)*math.Sin(slope)*math.Cos(az-aspect)
			out[y*g.W+x] = math.Max(0, math.Min(1, v))
		}
	}
	return out
}

// Bilinear samples the grid at fractional pixel coordinates (pixel centres at integers), clamped
// to the border.
func (g *Grid) Bilinear(x, y float64) float64 {
	x0, y0 := math.Floor(x), math.Floor(y)
	fx, fy := x-x0, y-y0
	ix, iy := int(x0), int(y0)
	a := float64(g.ClampedAt(ix, iy))*(1-fx) + float64(g.ClampedAt(ix+1, iy))*fx
	b := float64(g.ClampedAt(ix, iy+1))*(1-fx) + float64(g.ClampedAt(ix+1, iy+1))*fx
	return a*(1-fy) + b*fy
}
