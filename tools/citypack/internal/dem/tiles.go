package dem

import "math"

// BBox is a geographic bounding box in degrees.
type BBox struct {
	LatMin, LonMin, LatMax, LonMax float64
}

// earthCircumference at the equator, WGS84, in metres.
const earthCircumference = 40075016.685578488

// TileSize is the pixel edge of one slippy-map tile.
const TileSize = 256

// LonToPixelX converts a longitude to a fractional pixel coordinate in the
// global Web Mercator pixel grid at zoom z.
func LonToPixelX(lon float64, z int) float64 {
	return (lon + 180.0) / 360.0 * math.Exp2(float64(z)) * TileSize
}

// LatToPixelY converts a latitude to a fractional pixel coordinate. Y grows
// southward, so latMax maps to the smaller value.
func LatToPixelY(lat float64, z int) float64 {
	rad := lat * math.Pi / 180.0
	y := (1.0 - math.Log(math.Tan(rad)+1.0/math.Cos(rad))/math.Pi) / 2.0
	return y * math.Exp2(float64(z)) * TileSize
}

// MetersPerPixel is the ground resolution of the Mercator grid at a latitude.
// Mercator is conformal, so this holds for both axes and ground pixels stay
// square — a crop keeps its true aspect ratio without correction.
func MetersPerPixel(lat float64, z int) float64 {
	return earthCircumference * math.Cos(lat*math.Pi/180.0) / (math.Exp2(float64(z)) * TileSize)
}

// TileRange is the inclusive block of tiles covering a bbox at zoom z.
type TileRange struct {
	Z              int
	X0, Y0, X1, Y1 int
}

func (r TileRange) count() int { return (r.X1 - r.X0 + 1) * (r.Y1 - r.Y0 + 1) }

// TilesFor returns the tiles covering b at zoom z.
func TilesFor(b BBox, z int) TileRange {
	n := int(math.Exp2(float64(z)))
	clamp := func(v int) int {
		if v < 0 {
			return 0
		}
		if v > n-1 {
			return n - 1
		}
		return v
	}
	x0 := clamp(int(math.Floor(LonToPixelX(b.LonMin, z) / TileSize)))
	x1 := clamp(int(math.Ceil(LonToPixelX(b.LonMax, z)/TileSize)) - 1)
	y0 := clamp(int(math.Floor(LatToPixelY(b.LatMax, z) / TileSize)))
	y1 := clamp(int(math.Ceil(LatToPixelY(b.LatMin, z)/TileSize)) - 1)
	if x1 < x0 {
		x1 = x0
	}
	if y1 < y0 {
		y1 = y0
	}
	return TileRange{Z: z, X0: x0, Y0: y0, X1: x1, Y1: y1}
}

// nativeSize is the pixel size the bbox occupies at zoom z, before resampling.
// Each edge is rounded to a pixel boundary exactly as crop does, so the two
// always agree — rounding the span instead can differ by one pixel.
func nativeSize(b BBox, z int) (w, h int) {
	w = int(math.Round(LonToPixelX(b.LonMax, z))) - int(math.Round(LonToPixelX(b.LonMin, z)))
	h = int(math.Round(LatToPixelY(b.LatMin, z))) - int(math.Round(LatToPixelY(b.LatMax, z)))
	return
}

// autoZoom picks the smallest zoom whose native width reaches want pixels,
// clamped to the source's usable range.
func autoZoom(b BBox, want, maxZoom int) int {
	for z := 1; z < maxZoom; z++ {
		if w, _ := nativeSize(b, z); w >= want {
			return z
		}
	}
	return maxZoom
}

// widthMeters and heightMeters measure the bbox on the ground at its centre
// latitude, which is the scale the Mercator crop is rendered at.
func (b BBox) centerLat() float64 { return (b.LatMin + b.LatMax) / 2 }

func (b BBox) groundSize(z int) (w, h float64) {
	mpp := MetersPerPixel(b.centerLat(), z)
	pw, ph := nativeSize(b, z)
	return float64(pw) * mpp, float64(ph) * mpp
}
