package steps

import (
	"fmt"
	"log/slog"
	"math"
	"os"
	"path/filepath"
	"strings"

	"citypack/internal/geo"

	"github.com/fogleman/gg"
)

// previewSection renders CITYPACK_SECTION="name:x,y;x,y;…" to preview/section_<name>.png: a
// long section along that polyline, every 2 m: the terrain (brown) and the
// height of every edge within 12 m of the line (red: bridge or upper layer, blue: ramp, black:
// ground road). A debugging aid; nothing without the variable.
func previewSection(p *PackData, dir string) error {
	spec := os.Getenv("CITYPACK_SECTION")
	if spec == "" || p.Manifest.TerrainVersion == 0 {
		return nil
	}
	name, list, ok := strings.Cut(spec, ":")
	var way []geo.Pt
	for _, xy := range strings.Split(list, ";") {
		var q geo.Pt
		if _, err := fmt.Sscanf(xy, "%f,%f", &q.X, &q.Y); err == nil {
			way = append(way, q)
		}
	}
	if !ok || len(way) < 2 {
		return fmt.Errorf("CITYPACK_SECTION: want name:x,y;x,y;…")
	}
	L := geo.PolylineLength(way)
	at := func(s float64) geo.Pt {
		for k := 1; k < len(way); k++ {
			l := way[k].Dist(way[k-1])
			if s <= l || k == len(way)-1 {
				return way[k-1].Add(way[k].Sub(way[k-1]).Mul(math.Min(1, s/math.Max(l, 1e-9))))
			}
			s -= l
		}
		return way[len(way)-1]
	}
	t := newPackTerrain(p)
	type dot struct {
		s, z float64
		kind int
	}
	var terr []dot
	var dots []dot
	lo, hi := math.Inf(1), math.Inf(-1)
	for s := 0.0; s <= L; s += 2 {
		q := at(s)
		if z, ok := t.at(q); ok {
			terr = append(terr, dot{s: s, z: z})
			lo, hi = math.Min(lo, z), math.Max(hi, z)
		}
		for _, ed := range p.Graph.Edges {
			pts, zs := EdgePts(ed), edgeZ(ed)
			if len(zs) != len(pts) {
				continue
			}
			for k := 1; k < len(pts); k++ {
				c, tq := geo.ClosestOnSegment(q, pts[k-1], pts[k])
				if c.Dist(q) > 12 {
					continue
				}
				z := zs[k-1] + (zs[k]-zs[k-1])*tq
				kind := 0
				switch {
				case ed.Tunnel:
					continue
				case ed.Bridge || (ed.LayerFrom > 0 && ed.LayerTo > 0):
					kind = 2
				case ed.LayerFrom != ed.LayerTo:
					kind = 1
				}
				dots = append(dots, dot{s: s, z: z, kind: kind})
				lo, hi = math.Min(lo, z), math.Max(hi, z)
				break
			}
		}
	}
	const w, h, m = 1400.0, 500.0, 50.0
	dc := gg.NewContext(int(w), int(h))
	dc.SetHexColor("#ffffff")
	dc.Clear()
	px := func(s, z float64) (float64, float64) {
		return m + s/L*(w-2*m), h - m - (z-lo)/math.Max(1, hi-lo)*(h-2*m)
	}
	dc.SetHexColor("#8b5a2b")
	dc.SetLineWidth(2)
	for i, d := range terr {
		x, y := px(d.s, d.z)
		if i == 0 {
			dc.MoveTo(x, y)
		} else {
			dc.LineTo(x, y)
		}
	}
	dc.Stroke()
	colors := []string{"#000000", "#1d6fe0", "#d0021b"}
	for _, d := range dots {
		x, y := px(d.s, d.z)
		dc.SetHexColor(colors[d.kind])
		dc.DrawCircle(x, y, 2)
		dc.Fill()
	}
	dc.SetFontFace(previewFont(14))
	dc.SetHexColor("#000000")
	dc.DrawStringAnchored(fmt.Sprintf("%s: section %.0f m, game height %.1f..%.1f m; brown terrain, red deck/upper layer, blue ramp, black ground road", name, L, lo, hi), m, 20, 0, 0.5)
	out := filepath.Join(dir, "section_"+name+".png")
	slog.Info("preview section", "png", out)
	return dc.SavePNG(out)
}
