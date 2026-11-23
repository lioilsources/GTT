package steps

import (
	"fmt"
	"image"
	"image/color"
	"log/slog"
	"math"
	"path/filepath"
	"sort"

	"citypack/internal/geo"
	"citypack/internal/pb"

	"github.com/fogleman/gg"
	"github.com/golang/freetype/truetype"
	"golang.org/x/image/font"
	"golang.org/x/image/font/basicfont"
	"golang.org/x/image/font/gofont/goregular"
)

// previewFont is Go Regular (Latin Extended: Czech names keep their diacritics); basicfont
// is ASCII only.
func previewFont(size float64) font.Face {
	f, err := truetype.Parse(goregular.TTF)
	if err != nil {
		return basicfont.Face7x13
	}
	return truetype.NewFace(f, &truetype.Options{Size: size})
}

// Preview additions for terrain and nature (Prompts/02-METROPOLE_TERRAIN_PLAN.md ch. 4 preview):
// <city>_relief.png (hillshade over a height tint, the 10 steepest named streets) and
// <city>_nature.png (water and green classes, trees, labels). Flat packs get neither.

// previewFrame maps local metres to preview pixels.
type previewFrame struct {
	minX, maxY float64
	w, h       int
}

func newPreviewFrame(p *PackData) previewFrame {
	b := p.Manifest.Bounds
	minX, minY := float64(b.MinX)/10, float64(b.MinY)/10
	maxX, maxY := float64(b.MaxX)/10, float64(b.MaxY)/10
	return previewFrame{minX: minX, maxY: maxY,
		w: int(math.Ceil((maxX - minX) * previewPxPerM)), h: int(math.Ceil((maxY - minY) * previewPxPerM))}
}

func (f previewFrame) px(x, y float64) (float64, float64) {
	return (x - f.minX) * previewPxPerM, (f.maxY - y) * previewPxPerM
}

func (f previewFrame) m(px, py float64) geo.Pt {
	return geo.Pt{X: f.minX + px/previewPxPerM, Y: f.maxY - py/previewPxPerM}
}

// packShade looks up Chunk.shade like packTerrain looks up heights.
type packShade struct {
	chunkM, step float64
	n            int
	s            map[[2]int][]byte
}

func newPackShade(p *PackData) *packShade {
	cm := float64(p.Manifest.ChunkM)
	t := &packShade{chunkM: cm, step: float64(p.Manifest.TerrainGridM), s: map[[2]int][]byte{}}
	t.n = int(math.Round(cm/t.step)) + 1
	for _, c := range p.Chunks {
		if len(c.Shade) == t.n*t.n {
			t.s[[2]int{int(c.X), int(c.Y)}] = c.Shade
		}
	}
	return t
}

func (t *packShade) at(p geo.Pt) (float64, bool) {
	cx, cy := int(math.Floor(p.X/t.chunkM)), int(math.Floor(p.Y/t.chunkM))
	s, ok := t.s[[2]int{cx, cy}]
	if !ok {
		return 0, false
	}
	x := (p.X - float64(cx)*t.chunkM) / t.step
	y := (p.Y - float64(cy)*t.chunkM) / t.step
	i, j := min(int(math.Floor(x)), t.n-2), min(int(math.Floor(y)), t.n-2)
	fx, fy := x-float64(i), y-float64(j)
	g := func(a, b int) float64 { return float64(s[b*t.n+a]) }
	return (g(i, j)*(1-fx)+g(i+1, j)*fx)*(1-fy) + (g(i, j+1)*(1-fx)+g(i+1, j+1)*fx)*fy, true
}

// Steep is one entry of steepest.json: the steepest stretch of a named street.
type Steep struct {
	Name     string
	GradePct float64 // real grade (game grade / exaggeration), over at least steepWindowM
	LengthM  float64
	X, Y     float64 // middle of the stretch
	Edge     int
}

const steepWindowM = 60.0

// steepestStreets returns the n named ground streets with the steepest stretch of at least
// steepWindowM (whole edge when shorter but at least 2/3 of it), one entry per name.
func steepestStreets(p *PackData, n int) []Steep {
	g := p.Graph
	ex := float64(p.Manifest.Exaggeration)
	if ex <= 0 {
		ex = 1
	}
	best := map[string]Steep{}
	for ei, ed := range g.Edges {
		name := g.Names[ed.Name]
		if name == "" || ed.Tunnel || ed.Stairs || !groundEdge(ed) {
			continue
		}
		pts, zs := EdgePts(ed), edgeZ(ed)
		if len(zs) != len(pts) || len(pts) < 2 {
			continue
		}
		s := make([]float64, len(pts))
		for k := 1; k < len(pts); k++ {
			s[k] = s[k-1] + pts[k].Dist(pts[k-1])
		}
		total := s[len(s)-1]
		win := math.Min(steepWindowM, total)
		if win < steepWindowM*2/3 {
			continue
		}
		j := 0
		for i := range pts {
			for j < len(pts)-1 && s[j]-s[i] < win {
				j++
			}
			if s[j]-s[i] < win-1e-6 {
				break
			}
			gr := math.Abs(zs[j]-zs[i]) / (s[j] - s[i]) / ex * 100
			if cur, ok := best[name]; !ok || gr > cur.GradePct {
				mid := pts[i].Add(pts[j]).Mul(0.5)
				best[name] = Steep{Name: name, GradePct: math.Round(gr*10) / 10, LengthM: math.Round(s[j] - s[i]), X: math.Round(mid.X), Y: math.Round(mid.Y), Edge: ei}
			}
		}
	}
	out := make([]Steep, 0, len(best))
	for _, v := range best {
		out = append(out, v)
	}
	sort.Slice(out, func(a, b int) bool {
		if out[a].GradePct != out[b].GradePct {
			return out[a].GradePct > out[b].GradePct
		}
		return out[a].Name < out[b].Name
	})
	return out[:min(n, len(out))]
}

// heightTint: low green, middle ochre, high brown-white (t in 0..1).
func heightTint(t float64) (float64, float64, float64) {
	stops := [][4]float64{{0, 0.55, 0.72, 0.50}, {0.35, 0.85, 0.85, 0.60}, {0.7, 0.78, 0.62, 0.42}, {1, 0.95, 0.93, 0.90}}
	t = math.Max(0, math.Min(1, t))
	for k := 1; k < len(stops); k++ {
		if t <= stops[k][0] {
			a, b := stops[k-1], stops[k]
			u := (t - a[0]) / (b[0] - a[0])
			return a[1] + (b[1]-a[1])*u, a[2] + (b[2]-a[2])*u, a[3] + (b[3]-a[3])*u
		}
	}
	return stops[3][1], stops[3][2], stops[3][3]
}

// fillTriangles fills an indexed triangle list in one path. Every triangle is added
// counter-clockwise: under the nonzero rule two overlapping triangles of opposite winding would
// cancel and leave a hole that the game (which draws both) does not have.
func fillTriangles(dc *gg.Context, f previewFrame, verts []int32, idx []uint32) {
	for k := 0; k+2 < len(idx); k += 3 {
		var xs, ys [3]float64
		for v := 0; v < 3; v++ {
			i := int(idx[k+v])
			xs[v], ys[v] = f.px(float64(verts[2*i])/10, float64(verts[2*i+1])/10)
		}
		order := [3]int{0, 1, 2}
		if (xs[1]-xs[0])*(ys[2]-ys[0])-(ys[1]-ys[0])*(xs[2]-xs[0]) < 0 {
			order = [3]int{0, 2, 1}
		}
		dc.MoveTo(xs[order[0]], ys[order[0]])
		dc.LineTo(xs[order[1]], ys[order[1]])
		dc.LineTo(xs[order[2]], ys[order[2]])
		dc.ClosePath()
	}
	dc.Fill()
}

func drawEdgeLine(dc *gg.Context, f previewFrame, ed *pb.Edge, width float64) {
	for i := 0; i < len(ed.Points)/2; i++ {
		x, y := f.px(float64(ed.Points[2*i])/10, float64(ed.Points[2*i+1])/10)
		dc.LineTo(x, y)
	}
	dc.SetLineWidth(width)
	dc.Stroke()
}

// haloText draws s with a white outline.
func haloText(dc *gg.Context, s string, x, y, ax, ay float64, col string) {
	dc.SetHexColor("#ffffff")
	for _, d := range [][2]float64{{-1, 0}, {1, 0}, {0, -1}, {0, 1}, {-1, -1}, {1, 1}, {-1, 1}, {1, -1}} {
		dc.DrawStringAnchored(s, x+d[0], y+d[1], ax, ay)
	}
	dc.SetHexColor(col)
	dc.DrawStringAnchored(s, x, y, ax, ay)
}

func legend(dc *gg.Context, title string, rows []string, swatches []string) {
	lh := 17.0
	tw, _ := dc.MeasureString(title)
	w := tw + 20
	for _, r := range rows {
		rw, _ := dc.MeasureString(r)
		w = math.Max(w, rw+50)
	}
	h := lh*float64(len(rows)+1) + 12
	dc.SetRGBA(1, 1, 1, 0.88)
	dc.DrawRectangle(10, 10, w, h)
	dc.Fill()
	dc.SetHexColor("#000000")
	dc.DrawStringAnchored(title, 18, 10+lh, 0, 0)
	for i, r := range rows {
		y := 10 + lh*float64(i+2)
		x := 18.0
		if i < len(swatches) && swatches[i] != "" {
			dc.SetHexColor(swatches[i])
			dc.DrawRectangle(x, y-10, 14, 11)
			dc.Fill()
			x += 22
		}
		dc.SetHexColor("#000000")
		dc.DrawStringAnchored(r, x, y, 0, 0)
	}
}

// previewRelief writes <city>_relief.png and steepest.json; it returns the PNG path.
func previewRelief(e *Env, p *PackData, dir string) (string, error) {
	t, sh := newPackTerrain(p), newPackShade(p)
	f := newPreviewFrame(p)
	ex := float64(p.Manifest.Exaggeration)
	if ex <= 0 {
		ex = 1
	}
	lo, hi := math.Inf(1), math.Inf(-1)
	for _, zs := range t.z {
		for _, z := range zs {
			lo, hi = math.Min(lo, float64(z)/10), math.Max(hi, float64(z)/10)
		}
	}
	img := image.NewRGBA(image.Rect(0, 0, f.w, f.h))
	for py := 0; py < f.h; py++ {
		for px := 0; px < f.w; px++ {
			q := f.m(float64(px)+0.5, float64(py)+0.5)
			z, ok := t.at(q)
			if !ok {
				img.Set(px, py, color.RGBA{236, 230, 218, 255})
				continue
			}
			r, g, b := heightTint((z - lo) / math.Max(1, hi-lo))
			s, _ := sh.at(q)
			k := 0.35 + 0.65*s/255*255/180 // 128 (flat) → about 0.81
			k = math.Min(1.25, k)
			img.Set(px, py, color.RGBA{uint8(math.Min(255, 255*r*k)), uint8(math.Min(255, 255*g*k)), uint8(math.Min(255, 255*b*k)), 255})
		}
	}
	dc := gg.NewContextForRGBA(img)
	dc.SetLineCapRound()
	for _, c := range p.Chunks {
		for _, m := range c.Ground {
			if m.Kind != pb.GroundKind_WATER {
				continue
			}
			dc.SetRGBA(0.36, 0.56, 0.79, 0.85)
			fillTriangles(dc, f, m.Vertices, m.Indices)
		}
	}
	dc.SetRGBA(0.2, 0.2, 0.24, 0.55)
	for _, ed := range p.Graph.Edges {
		if ed.Kept && !ed.Tunnel {
			drawEdgeLine(dc, f, ed, 1.5)
		}
	}
	steep := steepestStreets(p, 10)
	dc.SetFontFace(previewFont(13))
	dc.SetHexColor("#d0021b")
	for _, s := range steep {
		for _, ed := range p.Graph.Edges {
			if p.Graph.Names[ed.Name] == s.Name && !ed.Tunnel {
				drawEdgeLine(dc, f, ed, 4)
			}
		}
	}
	rows := []string{fmt.Sprintf("height %.0f..%.0f m real (x%.1f in game)", lo/ex+float64(p.Manifest.Z0M), hi/ex+float64(p.Manifest.Z0M), ex)}
	sw := []string{""}
	for i, s := range steep {
		x, y := f.px(s.X, s.Y)
		dc.SetHexColor("#d0021b")
		dc.DrawCircle(x, y, 9)
		dc.Fill()
		dc.SetHexColor("#ffffff")
		dc.DrawStringAnchored(fmt.Sprint(i+1), x, y, 0.5, 0.35)
		haloText(dc, s.Name, x+12, y, 0, 0.35, "#5a0010")
		rows = append(rows, fmt.Sprintf("%2d  %-28s %4.1f %% over %.0f m", i+1, s.Name, s.GradePct, s.LengthM))
		sw = append(sw, "")
	}
	legend(dc, fmt.Sprintf("%s relief, 10 steepest named streets (real grade)", p.Manifest.Name), rows, sw)
	png := filepath.Join(dir, p.Manifest.CityId+"_relief.png")
	if err := dc.SavePNG(png); err != nil {
		return "", err
	}
	if err := writeJSON(filepath.Join(dir, "steepest.json"), steep); err != nil {
		return "", err
	}
	for i, s := range steep {
		slog.Info("preview: steep street", "rank", i+1, "name", s.Name, "grade_pct", s.GradePct, "over_m", s.LengthM)
	}
	return png, nil
}

var waterColor = map[pb.WaterClass]string{
	pb.WaterClass_WATER_NONE: "#5b8fc9", pb.WaterClass_WATER_SEA: "#2f5f9e", pb.WaterClass_WATER_RIVER: "#4a86cf",
	pb.WaterClass_WATER_CANAL: "#6fa8dc", pb.WaterClass_WATER_LAKE: "#3e9fbf", pb.WaterClass_WATER_SMALL: "#9fc5e8",
}

var greenColor = map[pb.GreenClass]string{
	pb.GreenClass_GREEN_NONE: "#a8c98f", pb.GreenClass_GREEN_WOOD: "#2e6b30", pb.GreenClass_GREEN_PARKLAND: "#5f9e4a",
	pb.GreenClass_GREEN_GARDEN: "#9bcf6e", pb.GreenClass_GREEN_CEMETERY: "#7d8f6a", pb.GreenClass_GREEN_GRASS: "#b9de8a",
	pb.GreenClass_GREEN_SAND: "#e8d8a0",
}

// previewNature writes <city>_nature.png; it returns the PNG path.
func previewNature(p *PackData, dir string) (string, error) {
	f := newPreviewFrame(p)
	dc := gg.NewContext(f.w, f.h)
	dc.SetHexColor("#f2efe8")
	dc.Clear()
	fillMesh := func(m *pb.Mesh) { fillTriangles(dc, f, m.Vertices, m.Indices) }
	waterN, greenN := map[pb.WaterClass]int{}, map[pb.GreenClass]int{}
	for _, c := range p.Chunks {
		for _, m := range c.Ground {
			switch m.Kind {
			case pb.GroundKind_PARK:
				dc.SetHexColor(greenColor[m.GreenClass])
				greenN[m.GreenClass]++
			case pb.GroundKind_WATER:
				dc.SetHexColor(waterColor[m.WaterClass])
				waterN[m.WaterClass]++
			case pb.GroundKind_PLAZA:
				dc.SetHexColor("#e4dccd")
			case pb.GroundKind_RAIL:
				dc.SetHexColor("#cfc8c0")
			default:
				continue
			}
			fillMesh(m)
		}
		dc.SetHexColor("#a7d3e8")
		for _, m := range c.Shore {
			fillMesh(m)
		}
	}
	dc.SetHexColor("#d6d1c8")
	dc.SetLineCapRound()
	for _, ed := range p.Graph.Edges {
		if !ed.Tunnel {
			drawEdgeLine(dc, f, ed, math.Max(1, float64(ed.WidthM)*previewPxPerM*0.8))
		}
	}
	dc.SetHexColor("#bdb6ab")
	for _, c := range p.Chunks {
		for _, bd := range c.Buildings {
			fillTriangles(dc, f, bd.Rings, bd.Roof)
		}
	}
	cm := float64(p.Manifest.ChunkM)
	trees := 0
	dc.SetHexColor("#1b4d1e")
	for _, c := range p.Chunks {
		for i := 0; i+2 < len(c.Trees); i += 3 {
			x, y := f.px(float64(c.X)*cm+float64(c.Trees[i]), float64(c.Y)*cm+float64(c.Trees[i+1]))
			r := 0.6 + 0.4*float64(c.Trees[i+2]&3)
			dc.DrawCircle(x, y, r)
			dc.Fill()
			trees++
		}
	}
	dc.SetFontFace(previewFont(13))
	for _, c := range p.Chunks {
		for _, l := range c.Labels {
			if len(l.Axis) < 2 {
				continue
			}
			mid := len(l.Axis) / 4 * 2
			x, y := f.px(float64(l.Axis[mid])/10, float64(l.Axis[mid+1])/10)
			col := "#14501a"
			if l.Water {
				col = "#0b3d78"
			}
			haloText(dc, l.Name, x, y, 0.5, 0.5, col)
		}
	}
	var rows, sw []string
	for _, wc := range []pb.WaterClass{pb.WaterClass_WATER_SEA, pb.WaterClass_WATER_RIVER, pb.WaterClass_WATER_CANAL, pb.WaterClass_WATER_LAKE, pb.WaterClass_WATER_SMALL, pb.WaterClass_WATER_NONE} {
		if waterN[wc] > 0 {
			rows, sw = append(rows, fmt.Sprintf("%s (%d)", wc, waterN[wc])), append(sw, waterColor[wc])
		}
	}
	for _, gc := range []pb.GreenClass{pb.GreenClass_GREEN_WOOD, pb.GreenClass_GREEN_PARKLAND, pb.GreenClass_GREEN_GARDEN, pb.GreenClass_GREEN_CEMETERY, pb.GreenClass_GREEN_GRASS, pb.GreenClass_GREEN_SAND, pb.GreenClass_GREEN_NONE} {
		if greenN[gc] > 0 {
			rows, sw = append(rows, fmt.Sprintf("%s (%d)", gc, greenN[gc])), append(sw, greenColor[gc])
		}
	}
	rows, sw = append(rows, "shore band"), append(sw, "#a7d3e8")
	rows, sw = append(rows, fmt.Sprintf("trees: %d", trees)), append(sw, "#1b4d1e")
	legend(dc, p.Manifest.Name+" nature classes (mesh counts)", rows, sw)
	png := filepath.Join(dir, p.Manifest.CityId+"_nature.png")
	return png, dc.SavePNG(png)
}
