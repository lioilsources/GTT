package steps

import (
	"fmt"
	"image"
	"image/color"
	"log/slog"
	"math"
	"os"
	"path/filepath"
	"strings"

	"citypack/internal/geo"
	"citypack/internal/pb"

	"github.com/fogleman/gg"
)

// previewCrop renders CITYPACK_CROP="x0,y0,x1,y1,name" (local metres) at 2 px/m to
// preview/crop_<name>.png: hillshaded terrain coloured by height, water tinted, kept road
// centrelines, and red where terrain inside water is above the water level. A debugging aid for
// before/after comparisons; it does nothing without the variable.
func previewCrop(p *PackData, dir string) error {
	spec := os.Getenv("CITYPACK_CROP")
	if spec == "" || p.Manifest.TerrainVersion == 0 {
		return nil
	}
	var x0, y0, x1, y1 float64
	var name string
	if _, err := fmt.Sscanf(strings.ReplaceAll(spec, ",", " "), "%f %f %f %f %s", &x0, &y0, &x1, &y1, &name); err != nil {
		return fmt.Errorf("CITYPACK_CROP: %w", err)
	}
	const ppm = 2.0
	w, h := int((x1-x0)*ppm), int((y1-y0)*ppm)
	t, sh := newPackTerrain(p), newPackShade(p)
	water := newMeshIndex(p, func(m *pb.Mesh) bool { return m.Kind == pb.GroundKind_WATER })
	lo, hi := math.Inf(1), math.Inf(-1)
	for py := 0; py < h; py += 4 {
		for px := 0; px < w; px += 4 {
			if z, ok := t.at(geo.Pt{X: x0 + float64(px)/ppm, Y: y1 - float64(py)/ppm}); ok {
				lo, hi = math.Min(lo, z), math.Max(hi, z)
			}
		}
	}
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for py := 0; py < h; py++ {
		for px := 0; px < w; px++ {
			q := geo.Pt{X: x0 + (float64(px)+0.5)/ppm, Y: y1 - (float64(py)+0.5)/ppm}
			z, ok := t.at(q)
			if !ok {
				continue
			}
			r, g, b := heightTint((z - lo) / math.Max(1, hi-lo))
			s, _ := sh.at(q)
			k := math.Min(1.25, 0.35+0.65*s/180)
			c := color.RGBA{uint8(math.Min(255, 255*r*k)), uint8(math.Min(255, 255*g*k)), uint8(math.Min(255, 255*b*k)), 255}
			if m, ok := water.at(q); ok {
				if z > float64(m.ZDm)/10+0.05 {
					c = color.RGBA{220, 30, 30, 255}
				} else {
					c = color.RGBA{uint8(float64(c.R) * 0.5), uint8(float64(c.G) * 0.6), 200, 255}
				}
			}
			img.Set(px, py, c)
		}
	}
	dc := gg.NewContextForRGBA(img)
	dc.SetRGBA(0.1, 0.1, 0.1, 0.8)
	dc.SetLineWidth(1.5)
	for _, ed := range p.Graph.Edges {
		if !ed.Kept {
			continue
		}
		dc.NewSubPath()
		for i := 0; i < len(ed.Points)/2; i++ {
			dc.LineTo((float64(ed.Points[2*i])/10-x0)*ppm, (y1-float64(ed.Points[2*i+1])/10)*ppm)
		}
		dc.Stroke()
	}
	dc.SetFontFace(previewFont(14))
	legend(dc, fmt.Sprintf("%s: terrain %.1f..%.1f m (game), red = terrain in water above its level", name, lo, hi), nil, nil)
	out := filepath.Join(dir, "crop_"+name+".png")
	slog.Info("preview crop", "png", out)
	return dc.SavePNG(out)
}
