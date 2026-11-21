package steps

import (
	"fmt"
	"html/template"
	"log/slog"
	"math"
	"os"
	"path/filepath"

	"citypack/internal/geo"
	"citypack/internal/pb"

	"github.com/fogleman/gg"
	"golang.org/x/image/font/basicfont"
)

const previewPxPerM = 0.5

var groundColor = map[pb.GroundKind]string{
	pb.GroundKind_WATER: "#5b8fc9",
	pb.GroundKind_PARK:  "#7fb069",
	pb.GroundKind_PLAZA: "#d9cfbf",
	pb.GroundKind_RAIL:  "#9a8f86",
}

// Preview renders run/citypack/<city>/preview/{city.png,index.html} from the packed output
// (METROPOLE_PLAN 5.3 step 10). The HTML overlays the PNG on OpenStreetMap tiles.
func Preview(e *Env) error {
	p, err := ReadPack(e.Out)
	if err != nil {
		return err
	}
	dir := e.W("preview")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	b := p.Manifest.Bounds
	minX, minY := float64(b.MinX)/10, float64(b.MinY)/10
	maxX, maxY := float64(b.MaxX)/10, float64(b.MaxY)/10
	w := int(math.Ceil((maxX - minX) * previewPxPerM))
	h := int(math.Ceil((maxY - minY) * previewPxPerM))
	dc := gg.NewContext(w, h)
	tx := func(x, y float64) (float64, float64) {
		return (x - minX) * previewPxPerM, (maxY - y) * previewPxPerM
	}
	pt := func(v []int32, i int) (float64, float64) { return tx(float64(v[2*i])/10, float64(v[2*i+1])/10) }

	dc.SetHexColor("#ece6da")
	dc.Clear()
	for _, kind := range []pb.GroundKind{pb.GroundKind_PARK, pb.GroundKind_PLAZA, pb.GroundKind_RAIL, pb.GroundKind_WATER} {
		dc.SetHexColor(groundColor[kind])
		for _, c := range p.Chunks {
			for _, m := range c.Ground {
				if m.Kind != kind {
					continue
				}
				for t := 0; t+2 < len(m.Indices); t += 3 {
					for k := 0; k < 3; k++ {
						x, y := pt(m.Vertices, int(m.Indices[t+k]))
						dc.LineTo(x, y)
					}
					dc.ClosePath()
				}
				dc.Fill()
			}
		}
	}
	drawEdges := func(filter func(*pb.Edge) bool, color string, scale float64) {
		dc.SetHexColor(color)
		dc.SetLineCapRound()
		for _, ed := range p.Graph.Edges {
			if !filter(ed) {
				continue
			}
			dc.SetLineWidth(math.Max(1, float64(ed.WidthM)*previewPxPerM*scale))
			for i := 0; i < len(ed.Points)/2; i++ {
				x, y := pt(ed.Points, i)
				dc.LineTo(x, y)
			}
			dc.Stroke()
		}
	}
	ground := func(ed *pb.Edge) bool { return !ed.Tunnel && ed.LayerFrom >= 0 && ed.LayerTo >= 0 }
	drawEdges(func(ed *pb.Edge) bool { return ground(ed) && !ed.Kept }, "#c9c1b3", 1)
	drawEdges(func(ed *pb.Edge) bool { return ground(ed) && ed.Kept }, "#5a5a63", 1)
	for _, c := range p.Chunks {
		for _, bd := range c.Buildings {
			hh := math.Min(1, float64(bd.HeightM)/250)
			col := fmt.Sprintf("#%02x%02x%02x", int(220-150*hh), int(170-110*hh), int(120-60*hh))
			if bd.Landmark > 0 {
				col = "#d64545"
			}
			dc.SetHexColor(col)
			for t := 0; t+2 < len(bd.Roof); t += 3 {
				for k := 0; k < 3; k++ {
					x, y := pt(bd.Rings, int(bd.Roof[t+k]))
					dc.LineTo(x, y)
				}
				dc.ClosePath()
			}
			dc.Fill()
		}
	}
	drawEdges(func(ed *pb.Edge) bool { return ed.Tunnel || ed.LayerFrom < 0 || ed.LayerTo < 0 }, "#e0a03080", 0.35)
	drawEdges(func(ed *pb.Edge) bool { return ed.LayerFrom > 0 || ed.LayerTo > 0 }, "#2b2b33", 0.8)
	dc.SetFontFace(basicfont.Face7x13)
	for _, l := range p.Landmarks.Items {
		x, y := tx(float64(l.X)/10, float64(l.Y)/10)
		dc.SetHexColor("#000000")
		dc.DrawCircle(x, y, 3)
		dc.Fill()
		dc.DrawStringAnchored(l.Name, x+5, y, 0, 0.5)
	}
	dc.SetHexColor("#1d6fe0")
	for _, s := range p.Spots.Items {
		x, y := tx(float64(s.ParkX)/10, float64(s.ParkY)/10)
		dc.DrawCircle(x, y, 5)
		dc.Fill()
	}
	sx, sy := tx(float64(p.Manifest.Start.X)/10, float64(p.Manifest.Start.Y)/10)
	dc.SetHexColor("#00c853")
	dc.DrawCircle(sx, sy, 7)
	dc.Fill()
	png := filepath.Join(dir, p.Manifest.CityId+".png")
	if err := dc.SavePNG(png); err != nil {
		return err
	}

	proj := geo.NewProjection(p.Manifest.OriginLat, p.Manifest.OriginLon)
	lon0, lat0 := proj.Inverse(geo.Pt{X: minX, Y: minY})
	lon1, lat1 := proj.Inverse(geo.Pt{X: maxX, Y: maxY})
	f, err := os.Create(filepath.Join(dir, "index.html"))
	if err != nil {
		return err
	}
	defer f.Close()
	err = previewHTML.Execute(f, map[string]any{
		"Name": p.Manifest.Name, "Img": filepath.Base(png),
		"S": lat0, "W": lon0, "N": lat1, "E": lon1,
		"Edges": len(p.Graph.Edges), "Chunks": len(p.Chunks), "Release": p.Manifest.OvertureRelease,
	})
	if err != nil {
		return err
	}
	slog.Info("preview", "png", png, "px", fmt.Sprintf("%dx%d", w, h))
	return nil
}

var previewHTML = template.Must(template.New("preview").Parse(`<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>citypack preview – {{.Name}}</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>html,body,#map{height:100%;margin:0}#ui{position:absolute;z-index:1000;top:10px;right:10px;background:#fff;padding:8px 12px;font:14px sans-serif;border-radius:6px;box-shadow:0 1px 4px #0004}</style>
</head><body><div id="map"></div>
<div id="ui"><b>{{.Name}}</b> · Overture {{.Release}} · {{.Edges}} edges · {{.Chunks}} chunks<br>
citypack opacity <input id="op" type="range" min="0" max="1" step="0.05" value="0.7"></div>
<script>
const b=[[{{.S}},{{.W}}],[{{.N}},{{.E}}]];
const map=L.map('map').fitBounds(b);
L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19,attribution:'© OpenStreetMap contributors'}).addTo(map);
const img=L.imageOverlay('{{.Img}}',b,{opacity:0.7}).addTo(map);
document.getElementById('op').oninput=e=>img.setOpacity(+e.target.value);
</script></body></html>
`))
