package dem

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"math"
	"testing"
)

func TestPixelMathAtOrigin(t *testing.T) {
	// Null Island sits exactly at the centre of the Mercator grid.
	for z := 0; z <= 14; z++ {
		half := math.Exp2(float64(z)) * TileSize / 2
		if got := LonToPixelX(0, z); math.Abs(got-half) > 1e-6 {
			t.Errorf("z=%d LonToPixelX(0) = %v, want %v", z, got, half)
		}
		if got := LatToPixelY(0, z); math.Abs(got-half) > 1e-6 {
			t.Errorf("z=%d LatToPixelY(0) = %v, want %v", z, got, half)
		}
	}
}

func TestMetersPerPixelEquator(t *testing.T) {
	// The classic figure: 156543.03 m/px at zoom 0 on the equator.
	if got := MetersPerPixel(0, 0); math.Abs(got-156543.03) > 0.01 {
		t.Errorf("MetersPerPixel(0,0) = %v, want ~156543.03", got)
	}
	// Every zoom level halves it.
	for z := 1; z <= 15; z++ {
		want := 156543.03392804097 / math.Exp2(float64(z))
		if got := MetersPerPixel(0, z); math.Abs(got-want) > 1e-6 {
			t.Errorf("z=%d: got %v, want %v", z, got, want)
		}
	}
}

func TestTilesForEverest(t *testing.T) {
	// Everest summit: 27.9881 N, 86.9250 E. Tile 12/3037/1716 is the one that
	// actually holds it — checked against the live tile, which peaks at 8748 m
	// on a coarse sample while its southern neighbour is 100 m lowland.
	b := BBox{LatMin: 27.9880, LonMin: 86.9249, LatMax: 27.9882, LonMax: 86.9251}
	r := TilesFor(b, 12)
	if r.X0 != 3037 || r.Y0 != 1716 {
		t.Errorf("got tile %d/%d, want 3037/1716", r.X0, r.Y0)
	}
	if r.count() != 1 {
		t.Errorf("a summit-sized bbox spans %d tiles, want 1", r.count())
	}
}

func TestTileRangeCoversBBox(t *testing.T) {
	p := struct{ BBox BBox }{BBox{LatMin: 45.78, LonMin: 6.80, LatMax: 45.88, LonMax: 6.92}} // Mont Blanc preset of terrain-fetch
	r := TilesFor(p.BBox, 12)
	// Every corner of the bbox must fall inside the fetched block.
	px0, px1 := LonToPixelX(p.BBox.LonMin, 12), LonToPixelX(p.BBox.LonMax, 12)
	py0, py1 := LatToPixelY(p.BBox.LatMax, 12), LatToPixelY(p.BBox.LatMin, 12)
	if px0 < float64(r.X0*TileSize) || px1 > float64((r.X1+1)*TileSize) {
		t.Errorf("x range %v..%v outside tiles %d..%d", px0, px1, r.X0, r.X1)
	}
	if py0 < float64(r.Y0*TileSize) || py1 > float64((r.Y1+1)*TileSize) {
		t.Errorf("y range %v..%v outside tiles %d..%d", py0, py1, r.Y0, r.Y1)
	}
}

// makeTerrariumPNG builds a tile whose every pixel encodes the same height.
func makeTerrariumPNG(t *testing.T, r, g, b uint8) []byte {
	t.Helper()
	img := image.NewNRGBA(image.Rect(0, 0, TileSize, TileSize))
	for y := 0; y < TileSize; y++ {
		for x := 0; x < TileSize; x++ {
			img.SetNRGBA(x, y, color.NRGBA{R: r, G: g, B: b, A: 255})
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func TestDecodeTerrarium(t *testing.T) {
	cases := []struct {
		r, g, b uint8
		want    float64
	}{
		{128, 0, 0, 0},               // the encoding's zero point
		{128, 0, 128, 0.5},           // blue channel is 1/256 m
		{162, 145, 0, 8849},          // Everest
		{127, 255, 255, -0.00390625}, // just below sea level
		{0, 0, 0, -32768},            // floor
	}
	for _, c := range cases {
		g, err := DecodeTerrarium(makeTerrariumPNG(t, c.r, c.g, c.b))
		if err != nil {
			t.Fatal(err)
		}
		if got := float64(g.At(7, 11)); math.Abs(got-c.want) > 1e-4 {
			t.Errorf("decode(%d,%d,%d) = %v, want %v", c.r, c.g, c.b, got, c.want)
		}
	}
}

func TestMosaicPlacesTilesByPosition(t *testing.T) {
	r := TileRange{Z: 12, X0: 10, Y0: 20, X1: 11, Y1: 20}
	tiles := []Tile{
		// Deliberately out of order: the mosaic must place by X/Y, not by index.
		{X: 11, Y: 20, PNG: makeTerrariumPNG(t, 133, 0, 0)}, // 1280 m
		{X: 10, Y: 20, PNG: makeTerrariumPNG(t, 130, 0, 0)}, // 512 m
	}
	m, err := Mosaic(tiles, r)
	if err != nil {
		t.Fatal(err)
	}
	if m.W != 512 || m.H != 256 {
		t.Fatalf("mosaic is %dx%d, want 512x256", m.W, m.H)
	}
	if got := m.At(5, 5); math.Abs(float64(got)-512) > 1e-3 {
		t.Errorf("left tile = %v, want 512", got)
	}
	if got := m.At(300, 5); math.Abs(float64(got)-1280) > 1e-3 {
		t.Errorf("right tile = %v, want 1280", got)
	}
}

func TestResampleKeepsConstantField(t *testing.T) {
	g := NewGrid(64, 64)
	for i := range g.Data {
		g.Data[i] = 1234.5
	}
	for _, size := range []int{16, 64, 200} {
		out := Resample(g, size, size)
		for _, v := range out.Data {
			if math.Abs(float64(v)-1234.5) > 1e-2 {
				t.Fatalf("resample to %d: got %v, want 1234.5", size, v)
			}
		}
	}
}

func TestResampleKeepsLinearRamp(t *testing.T) {
	// A ramp is the case an anti-aliasing filter must not distort: the mean of
	// a linear function equals its value at the centre of the window.
	const n = 128
	g := NewGrid(n, n)
	for y := 0; y < n; y++ {
		for x := 0; x < n; x++ {
			g.Data[y*n+x] = float32(x) * 10
		}
	}
	for _, size := range []int{32, 256} {
		out := Resample(g, size, size)
		scale := float64(size) / float64(n)
		// Skip the border, where edge clamping legitimately bends the ramp.
		for x := 4; x < size-4; x++ {
			srcX := (float64(x)+0.5)/scale - 0.5
			want := srcX * 10
			if got := float64(out.At(x, size/2)); math.Abs(got-want) > 0.5 {
				t.Fatalf("resample to %d at x=%d: got %v, want %v", size, x, got, want)
			}
		}
	}
}

func TestResampleDownscaleAveragesInsteadOfPointSampling(t *testing.T) {
	// Alternating spikes: point sampling would return the spike value (or the
	// floor); a proper filter returns something near the mean.
	const n = 64
	g := NewGrid(n, n)
	for y := 0; y < n; y++ {
		for x := 0; x < n; x++ {
			if x%2 == 0 {
				g.Data[y*n+x] = 1000
			}
		}
	}
	out := Resample(g, 8, 8)
	for x := 1; x < 7; x++ {
		v := float64(out.At(x, 4))
		if v < 300 || v > 700 {
			t.Fatalf("downscaled spike field at x=%d = %v, want near the 500 mean", x, v)
		}
	}
}

func TestFitSize(t *testing.T) {
	cases := []struct{ w, h, max, wantW, wantH int }{
		{1000, 500, 0, 1000, 500},    // no cap
		{1000, 500, 4096, 1000, 500}, // already inside
		{8192, 4096, 4096, 4096, 2048},
		{4096, 8192, 4096, 2048, 4096}, // portrait caps on height
	}
	for _, c := range cases {
		w, h := fitSize(c.w, c.h, c.max)
		if w != c.wantW || h != c.wantH {
			t.Errorf("fitSize(%d,%d,%d) = %d,%d want %d,%d", c.w, c.h, c.max, w, h, c.wantW, c.wantH)
		}
	}
}

func TestCropMatchesBBoxSize(t *testing.T) {
	b := BBox{LatMin: 49.45, LonMin: 18.20, LatMax: 49.60, LonMax: 18.50} // Beskydy preset of terrain-fetch
	z := 12
	r := TilesFor(b, z)
	m := NewGrid((r.X1-r.X0+1)*TileSize, (r.Y1-r.Y0+1)*TileSize)
	for i := range m.Data {
		m.Data[i] = float32(i % 100)
	}
	c, err := Crop(m, b, r)
	if err != nil {
		t.Fatal(err)
	}
	wantW, wantH := nativeSize(b, z)
	if c.W != wantW || c.H != wantH {
		t.Errorf("crop is %dx%d, want the native %dx%d", c.W, c.H, wantW, wantH)
	}
}

func TestDecodeGSI(t *testing.T) {
	img := image.NewNRGBA(image.Rect(0, 0, 3, 1))
	enc := func(x, v int) { img.Set(x, 0, color.NRGBA{uint8(v >> 16), uint8(v >> 8), uint8(v), 255}) }
	enc(0, 1234)    // 12.34 m
	enc(1, 1<<23)   // no data
	enc(2, 1<<24-5) // −0.05 m
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	g, err := DecodeGSI(buf.Bytes())
	if err != nil {
		t.Fatal(err)
	}
	if math.Abs(float64(g.Data[0])-12.34) > 1e-4 || !math.IsNaN(float64(g.Data[1])) || math.Abs(float64(g.Data[2])+0.05) > 1e-4 {
		t.Fatalf("got %v", g.Data)
	}
}
