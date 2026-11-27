package steps

import (
	"math"
	"os"
	"path/filepath"
	"sort"

	"citypack/internal/pb"

	"github.com/fogleman/gg"
)

// Preview colours only (the game reads design/tokens.json color.model).
var previewRole = map[pb.ModelRole][3]float64{
	pb.ModelRole_ROLE_WALL:   {0.91, 0.86, 0.76},
	pb.ModelRole_ROLE_ROOF:   {0.55, 0.36, 0.30},
	pb.ModelRole_ROLE_COPPER: {0.36, 0.62, 0.52},
	pb.ModelRole_ROLE_STONE:  {0.70, 0.68, 0.64},
	pb.ModelRole_ROLE_GLASS:  {0.55, 0.70, 0.80},
	pb.ModelRole_ROLE_GOLD:   {0.85, 0.70, 0.30},
}

// previewModel writes preview/models/<id>.png: the roof plan from above (left) and the model
// seen obliquely from the south-west (right).
func (e *Env) previewModel(m *pb.Model, exag float64) error {
	dir := e.W(filepath.Join("preview", "models"))
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	const S = 900
	dc := gg.NewContext(2*S, S)
	dc.SetRGB(0.96, 0.95, 0.92)
	dc.Clear()
	// Top: roof plan.
	x1, y1, x2, y2 := math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)
	for _, pp := range m.RoofPlan {
		for i := 0; i+1 < len(pp.Points); i += 2 {
			x, y := float64(pp.Points[i])/10, float64(pp.Points[i+1])/10
			x1, y1, x2, y2 = math.Min(x1, x), math.Min(y1, y), math.Max(x2, x), math.Max(y2, y)
		}
	}
	if x2 > x1 {
		sc := 0.92 * S / math.Max(x2-x1, y2-y1)
		ox, oy := S/2-sc*(x1+x2)/2, S/2+sc*(y1+y2)/2
		for _, pp := range m.RoofPlan {
			g := 0.35 + 0.17*float64(pp.Shade)
			dc.SetRGB(g, g*0.92, g*0.85)
			for k := 0; k+2 < len(pp.Triangles); k += 3 {
				for j := 0; j < 3; j++ {
					i := pp.Triangles[k+j]
					dc.LineTo(ox+sc*float64(pp.Points[2*i])/10, oy-sc*float64(pp.Points[2*i+1])/10)
				}
				dc.ClosePath()
				dc.Fill()
			}
		}
	}
	// Oblique: orthographic from azimuth 225° (south-west), 30° down, painter's order.
	type tri struct {
		p     [3][2]float64
		depth float64
		col   [3]float64
	}
	az, el := 225*math.Pi/180, 30*math.Pi/180
	fx, fy := math.Sin(az), math.Cos(az) // view direction (from the camera into the scene) is −(fx, fy)
	var tris []tri
	px1, py1, px2, py2 := math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)
	for _, part := range m.Parts {
		pos := func(i uint32) v3 {
			return v3{
				float64(part.AnchorX+part.Positions[3*i]) / 10,
				float64(part.AnchorY+part.Positions[3*i+1]) / 10,
				float64(part.BaseZDm)/10 + float64(part.Positions[3*i+2])/10,
			}
		}
		for k := 0; k+2 < len(part.Triangles); k += 3 {
			a, b, c := pos(part.Triangles[k]), pos(part.Triangles[k+1]), pos(part.Triangles[k+2])
			n := b.sub(a).cross(c.sub(a))
			if n.norm() < 1e-9 {
				continue
			}
			light := 0.55 + 0.45*math.Max(0, n.dot(sunDir)/n.norm())
			base := previewRole[pb.ModelRole(part.Roles[k/3])]
			t := tri{col: [3]float64{base[0] * light, base[1] * light, base[2] * light}}
			for j, v := range []v3{a, b, c} {
				// Screen: u along the right of the view, w up.
				u := v.x*fy - v.y*fx
				d := -(v.x*fx + v.y*fy)
				w := v.z*math.Cos(el) + d*math.Sin(el)
				t.p[j] = [2]float64{u, w}
				t.depth += d*math.Cos(el) - v.z*math.Sin(el)
				px1, py1, px2, py2 = math.Min(px1, u), math.Min(py1, w), math.Max(px2, u), math.Max(py2, w)
			}
			tris = append(tris, t)
		}
	}
	sort.Slice(tris, func(i, j int) bool { return tris[i].depth > tris[j].depth })
	if px2 > px1 {
		sc := 0.92 * S / math.Max(px2-px1, py2-py1)
		ox, oy := S+S/2-sc*(px1+px2)/2, S/2+sc*(py1+py2)/2
		for _, t := range tris {
			dc.SetRGB(t.col[0], t.col[1], t.col[2])
			for _, p := range t.p {
				dc.LineTo(ox+sc*p[0], oy-sc*p[1])
			}
			dc.ClosePath()
			dc.FillPreserve()
			dc.SetLineWidth(0.4)
			dc.Stroke()
		}
	}
	_ = exag
	return dc.SavePNG(filepath.Join(dir, m.LandmarkId+".png"))
}
