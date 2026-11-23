package dem

import (
	"bytes"
	"fmt"
	"image"
	"image/png"
	"math"
)

// Grid is a north-up raster of elevations in metres, row-major.
type Grid struct {
	W, H int
	Data []float32
}

func NewGrid(w, h int) *Grid { return &Grid{W: w, H: h, Data: make([]float32, w*h)} }

func (g *Grid) At(x, y int) float32 { return g.Data[y*g.W+x] }

// ClampedAt samples with edge clamping, for resample kernels that reach past
// the border.
func (g *Grid) ClampedAt(x, y int) float32 {
	if x < 0 {
		x = 0
	} else if x >= g.W {
		x = g.W - 1
	}
	if y < 0 {
		y = 0
	} else if y >= g.H {
		y = g.H - 1
	}
	return g.Data[y*g.W+x]
}

func (g *Grid) MinMax() (min, max float32) {
	min, max = g.Data[0], g.Data[0]
	for _, v := range g.Data {
		if v < min {
			min = v
		}
		if v > max {
			max = v
		}
	}
	return
}

// DecodeTerrarium turns one terrarium PNG into elevations in metres:
//
//	height = R*256 + G + B/256 - 32768
func DecodeTerrarium(b []byte) (*Grid, error) {
	img, err := png.Decode(bytes.NewReader(b))
	if err != nil {
		return nil, err
	}
	bounds := img.Bounds()
	w, h := bounds.Dx(), bounds.Dy()
	g := NewGrid(w, h)

	// Fast path: terrarium tiles are 8-bit RGB(A), which decodes to NRGBA.
	if nrgba, ok := img.(*image.NRGBA); ok {
		for y := 0; y < h; y++ {
			row := nrgba.Pix[y*nrgba.Stride:]
			for x := 0; x < w; x++ {
				r, gg, bb := row[x*4], row[x*4+1], row[x*4+2]
				g.Data[y*w+x] = float32(float64(r)*256 + float64(gg) + float64(bb)/256 - 32768)
			}
		}
		return g, nil
	}
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			r, gg, bb, _ := img.At(bounds.Min.X+x, bounds.Min.Y+y).RGBA()
			// RGBA() returns 16-bit values; terrarium is 8-bit per channel.
			g.Data[y*w+x] = float32(float64(r>>8)*256 + float64(gg>>8) + float64(bb>>8)/256 - 32768)
		}
	}
	return g, nil
}

// mosaic stitches fetched tiles into one grid covering the whole tile range.
func Mosaic(tiles []Tile, r TileRange) (*Grid, error) {
	cols, rows := r.X1-r.X0+1, r.Y1-r.Y0+1
	out := NewGrid(cols*TileSize, rows*TileSize)
	for _, t := range tiles {
		g, err := DecodeTerrarium(t.PNG)
		if err != nil {
			return nil, fmt.Errorf("tile %d/%d/%d: %w", r.Z, t.X, t.Y, err)
		}
		if g.W != TileSize || g.H != TileSize {
			return nil, fmt.Errorf("tile %d/%d/%d: got %dx%d, want %dx%d",
				r.Z, t.X, t.Y, g.W, g.H, TileSize, TileSize)
		}
		ox, oy := (t.X-r.X0)*TileSize, (t.Y-r.Y0)*TileSize
		for y := 0; y < TileSize; y++ {
			copy(out.Data[(oy+y)*out.W+ox:(oy+y)*out.W+ox+TileSize], g.Data[y*TileSize:(y+1)*TileSize])
		}
	}
	return out, nil
}

// crop cuts the exact bbox out of a tile mosaic.
func Crop(m *Grid, b BBox, r TileRange) (*Grid, error) {
	originX := float64(r.X0 * TileSize)
	originY := float64(r.Y0 * TileSize)

	x0 := int(math.Round(LonToPixelX(b.LonMin, r.Z) - originX))
	x1 := int(math.Round(LonToPixelX(b.LonMax, r.Z) - originX))
	y0 := int(math.Round(LatToPixelY(b.LatMax, r.Z) - originY))
	y1 := int(math.Round(LatToPixelY(b.LatMin, r.Z) - originY))

	if x0 < 0 {
		x0 = 0
	}
	if y0 < 0 {
		y0 = 0
	}
	if x1 > m.W {
		x1 = m.W
	}
	if y1 > m.H {
		y1 = m.H
	}
	w, h := x1-x0, y1-y0
	if w < 2 || h < 2 {
		return nil, fmt.Errorf("crop is %dx%d px — bbox too small for zoom %d", w, h, r.Z)
	}

	out := NewGrid(w, h)
	for y := 0; y < h; y++ {
		copy(out.Data[y*w:(y+1)*w], m.Data[(y0+y)*m.W+x0:(y0+y)*m.W+x0+w])
	}
	return out, nil
}

// catmullRom is the interpolating cubic used for resampling, support 2 px.
func catmullRom(x float64) float64 {
	x = math.Abs(x)
	switch {
	case x < 1:
		return 1.5*x*x*x - 2.5*x*x + 1
	case x < 2:
		return -0.5*x*x*x + 2.5*x*x - 4*x + 2
	}
	return 0
}

// resample scales a grid to w×h. The kernel widens when downscaling, which
// averages every source pixel that falls in an output pixel instead of point
// sampling it — without that, ridge lines alias into broken spikes.
func Resample(g *Grid, w, h int) *Grid {
	if w == g.W && h == g.H {
		return g
	}
	tmp := resampleAxis(g, w, true)
	return resampleAxis(tmp, h, false)
}

func resampleAxis(g *Grid, target int, horizontal bool) *Grid {
	srcLen := g.H
	if horizontal {
		srcLen = g.W
	}
	if target == srcLen {
		return g
	}

	var out *Grid
	if horizontal {
		out = NewGrid(target, g.H)
	} else {
		out = NewGrid(g.W, target)
	}

	scale := float64(target) / float64(srcLen)
	filterScale := 1.0
	if scale < 1 {
		filterScale = 1 / scale // widen for anti-aliased downscale
	}
	support := 2.0 * filterScale

	// Precompute weights per output index — they repeat down every row/column.
	type contrib struct {
		start   int
		weights []float64
	}
	contribs := make([]contrib, target)
	for i := 0; i < target; i++ {
		center := (float64(i)+0.5)/scale - 0.5
		start := int(math.Ceil(center - support))
		end := int(math.Floor(center + support))
		ws := make([]float64, 0, end-start+1)
		sum := 0.0
		for j := start; j <= end; j++ {
			wgt := catmullRom((float64(j) - center) / filterScale)
			ws = append(ws, wgt)
			sum += wgt
		}
		if sum != 0 {
			for k := range ws {
				ws[k] /= sum
			}
		}
		contribs[i] = contrib{start: start, weights: ws}
	}

	if horizontal {
		for y := 0; y < g.H; y++ {
			for i, c := range contribs {
				acc := 0.0
				for k, wgt := range c.weights {
					acc += wgt * float64(g.ClampedAt(c.start+k, y))
				}
				out.Data[y*out.W+i] = float32(acc)
			}
		}
	} else {
		for i, c := range contribs {
			for x := 0; x < g.W; x++ {
				acc := 0.0
				for k, wgt := range c.weights {
					acc += wgt * float64(g.ClampedAt(x, c.start+k))
				}
				out.Data[i*out.W+x] = float32(acc)
			}
		}
	}
	return out
}

// fitSize scales w×h down so neither axis exceeds max, keeping the aspect
// ratio. A max of 0, or an image already inside it, is left alone.
func fitSize(w, h, max int) (int, int) {
	if max <= 0 || (w <= max && h <= max) {
		return w, h
	}
	s := math.Min(float64(max)/float64(w), float64(max)/float64(h))
	nw, nh := int(math.Round(float64(w)*s)), int(math.Round(float64(h)*s))
	if nw < 1 {
		nw = 1
	}
	if nh < 1 {
		nh = 1
	}
	return nw, nh
}
