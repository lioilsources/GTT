// Command phototrial is a local experiment (not part of the pipeline, no spec): it bakes the IPR
// photorealistic 3D mesh (OBJ + JPG tiles in S-JTSK, CC BY 4.0 © IPR Praha) onto the LOD2 walls and
// roofs of one landmark building in models.pb (St. Vitus Cathedral, _70215) and writes a small
// atlas plus per-triangle UVs next to the pack. The web client reads them only behind ?photo=1.
//
//	phototrial -pack build/packs/prague -gml run/citypack/prague/raw/models/BD3_Prah_7-1.gml \
//	  -mesh run/citypack/prague/raw/mesh -building _70215 -size 2048 -out run/citypack/prague/photo
//
// Output: atlas_<size>.jpg, photo.json ({model, size, parts: [{part, tris}]}) and uv.bin
// (uint16 u, v per triangle corner, parts in photo.json order, triangles in part order).
package main

import (
	"compress/gzip"
	"encoding/binary"
	"encoding/json"
	"flag"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"io"
	"log"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"bufio"

	"citypack/internal/citygml"
	"citypack/internal/duck"
	"citypack/internal/geo"
	"citypack/internal/pb"

	"google.golang.org/protobuf/proto"
)

type v3 struct{ x, y, z float64 }

func (a v3) sub(b v3) v3      { return v3{a.x - b.x, a.y - b.y, a.z - b.z} }
func (a v3) add(b v3) v3      { return v3{a.x + b.x, a.y + b.y, a.z + b.z} }
func (a v3) mul(k float64) v3 { return v3{a.x * k, a.y * k, a.z * k} }
func (a v3) dot(b v3) float64 { return a.x*b.x + a.y*b.y + a.z*b.z }
func (a v3) cross(b v3) v3    { return v3{a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x} }
func (a v3) norm() float64    { return math.Sqrt(a.dot(a)) }
func (a v3) unit() v3         { return a.mul(1 / a.norm()) }

func main() {
	pack := flag.String("pack", "build/packs/prague", "pack directory")
	gml := flag.String("gml", "run/citypack/prague/raw/models/BD3_Prah_7-1.gml", "CityGML sheet")
	meshDir := flag.String("mesh", "run/citypack/prague/raw/mesh", "OBJ tiles")
	bid := flag.String("building", "_70215", "source building id")
	model := flag.String("model", "prague_castle", "landmark id")
	size := flag.Int("size", 2048, "atlas size")
	out := flag.String("out", "run/citypack/prague/photo", "output dir")
	fill := flag.Float64("fill", 0.62, "target atlas fill")
	gain := flag.Float64("gain", 1, "exposure gain on the photo colours (the photos are dark)")
	bboxOnly := flag.Bool("bbox", false, "print the building's S-JTSK box and exit")
	flag.Parse()

	// The building in source coordinates: footprint, foot and ground plane (as buildPart).
	gb := readBuilding(*gml, *bid)
	x1, y1, x2, y2 := math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)
	foot, all := math.Inf(1), math.Inf(1)
	var gv []citygml.V3
	for _, p := range gb.Polys {
		for _, v := range p.Rings[0] {
			x1, y1, x2, y2 = math.Min(x1, v.X), math.Min(y1, v.Y), math.Max(x2, v.X), math.Max(y2, v.Y)
			all = math.Min(all, v.Z)
			if p.Kind == citygml.Ground {
				foot = math.Min(foot, v.Z)
			}
		}
		if p.Kind == citygml.Ground {
			gv = append(gv, p.Rings[0]...)
		}
	}
	if math.IsInf(foot, 1) {
		foot = all
	}
	log.Printf("building %s: x %.1f…%.1f y %.1f…%.1f foot %.2f", *bid, x1, x2, y1, y2, foot)
	if *bboxOnly {
		return
	}
	plane, planeOK := groundPlane(gv)

	var mf pb.Manifest
	mustProto(filepath.Join(*pack, "manifest.pb"), &mf)
	var ms pb.Models
	mustProto(filepath.Join(*pack, "models.pb"), &ms)
	exag := float64(mf.GetExaggeration())
	if exag <= 0 {
		exag = 1
	}
	proj := geo.NewProjection(mf.GetOriginLat(), mf.GetOriginLon())
	af := fitQuad("EPSG:5514", x1-300, y1-300, x2+300, y2+300, proj)

	var m *pb.Model
	for _, mm := range ms.Models {
		if mm.LandmarkId == *model {
			m = mm
		}
	}
	if m == nil {
		log.Fatalf("model %s not in models.pb", *model)
	}
	var parts []int
	for i, p := range m.Parts {
		if p.SourceId == *bid {
			parts = append(parts, i)
		}
	}
	if len(parts) == 0 {
		log.Fatalf("no part with source %s", *bid)
	}
	log.Printf("exaggeration %.3f, parts %v, plane %v", exag, parts, planeOK)

	// Photo mesh, cropped to the building (+12 m), into the space of the first part
	// (anchor-relative metres, z above the foot as zrel).
	p0 := m.Parts[parts[0]]
	ax, ay := float64(p0.AnchorX)/10, float64(p0.AnchorY)/10
	toModel := func(x, y, z float64) v3 {
		q := af.apply(geo.Pt{X: x, Y: y})
		zr := z - foot
		if planeOK && exag > 1 {
			zr += (exag - 1) * (plane[0] + plane[1]*x + plane[2]*y - foot)
		}
		return v3{q.X - ax, q.Y - ay, zr}
	}
	const margin = 12.0
	var tris []mtri
	var texs []image.Image
	tiles, _ := filepath.Glob(filepath.Join(*meshDir, "*-mesh.obj"))
	for _, t := range tiles {
		bx1, by1, bx2, by2 := objBox(t)
		if bx2 < x1-margin || bx1 > x2+margin || by2 < y1-margin || by1 > y2+margin {
			continue
		}
		ti := len(texs)
		jp := strings.TrimSuffix(t, "-mesh.obj") + "-texture-0.jpg"
		img := mustJPEG(jp)
		texs = append(texs, img)
		n0 := len(tris)
		tris = readOBJ(t, ti, x1-margin, y1-margin, x2+margin, y2+margin, toModel, tris)
		log.Printf("tile %s: %d triangles near the building, texture %v", filepath.Base(t), len(tris)-n0, img.Bounds().Size())
	}
	if len(tris) == 0 {
		log.Fatal("no photo mesh triangles near the building")
	}
	bvh := buildBVH(tris)
	log.Printf("photo mesh box in model space: %v … %v", bvh.nodes[0].lo, bvh.nodes[0].hi)

	// LOD2 triangles of the parts in the first part's space.
	type ltri struct {
		part, idx int
		p         [3]v3
		n         v3
		area      float64
		chart     int
	}
	var lt []ltri
	var vid [][3]int // global vertex ids for adjacency
	base := 0
	for _, pi := range parts {
		p := m.Parts[pi]
		dx, dy := float64(p.AnchorX)/10-ax, float64(p.AnchorY)/10-ay
		dz := float64(p.BaseZDm-p0.BaseZDm) / 10 // parts of one building share the base
		pos := func(i uint32) v3 {
			return v3{float64(p.Positions[3*i])/10 + dx, float64(p.Positions[3*i+1])/10 + dy, float64(p.Positions[3*i+2])/10 + dz}
		}
		for k := 0; k+2 < len(p.Triangles); k += 3 {
			a, b, c := p.Triangles[k], p.Triangles[k+1], p.Triangles[k+2]
			t := ltri{part: pi, idx: k / 3, p: [3]v3{pos(a), pos(b), pos(c)}}
			cr := t.p[1].sub(t.p[0]).cross(t.p[2].sub(t.p[0]))
			t.area = cr.norm() / 2
			if t.area > 1e-9 {
				t.n = cr.unit()
			} else {
				t.n = v3{0, 0, 1}
			}
			lt = append(lt, t)
			vid = append(vid, [3]int{base + int(a), base + int(b), base + int(c)})
		}
		base += len(p.Positions) / 3
	}
	// Charts: triangles sharing an edge and (almost) a plane.
	par := make([]int, len(lt))
	for i := range par {
		par[i] = i
	}
	var find func(int) int
	find = func(i int) int {
		for par[i] != i {
			par[i] = par[par[i]]
			i = par[i]
		}
		return i
	}
	edges := map[[2]int][]int{}
	for i, v := range vid {
		for e := 0; e < 3; e++ {
			a, b := v[e], v[(e+1)%3]
			if a > b {
				a, b = b, a
			}
			edges[[2]int{a, b}] = append(edges[[2]int{a, b}], i)
		}
	}
	for _, ts := range edges {
		for i := 0; i < len(ts); i++ {
			for j := i + 1; j < len(ts); j++ {
				a, b := lt[ts[i]], lt[ts[j]]
				if a.n.dot(b.n) > 0.996 && math.Abs(b.p[0].sub(a.p[0]).dot(a.n)) < 0.08 {
					par[find(ts[i])] = find(ts[j])
				}
			}
		}
	}
	type chart struct {
		tris           []int
		n, t, b, o     v3
		u0, v0, u1, v1 float64
		w, h, x, y     int
	}
	cm := map[int]*chart{}
	var charts []*chart
	for i := range lt {
		r := find(i)
		c := cm[r]
		if c == nil {
			c = &chart{u0: math.Inf(1), v0: math.Inf(1), u1: math.Inf(-1), v1: math.Inf(-1)}
			cm[r] = c
			charts = append(charts, c)
		}
		c.tris = append(c.tris, i)
		lt[i].chart = len(charts) - 1
	}
	totalArea := 0.0
	for _, c := range charts {
		var n v3
		for _, i := range c.tris {
			n = n.add(lt[i].n.mul(lt[i].area))
		}
		if n.norm() < 1e-9 {
			n = lt[c.tris[0]].n
		}
		c.n = n.unit()
		if math.Abs(c.n.z) < 0.9 {
			c.t = v3{-c.n.y, c.n.x, 0}.unit()
		} else {
			c.t = v3{1, 0, 0}
		}
		c.b = c.n.cross(c.t).unit()
		c.o = lt[c.tris[0]].p[0]
		for _, i := range c.tris {
			totalArea += lt[i].area
			for _, p := range lt[i].p {
				u, v := p.sub(c.o).dot(c.t), p.sub(c.o).dot(c.b)
				c.u0, c.v0, c.u1, c.v1 = math.Min(c.u0, u), math.Min(c.v0, v), math.Max(c.u1, u), math.Max(c.v1, v)
			}
		}
	}
	{
		lo, hi := v3{math.Inf(1), math.Inf(1), math.Inf(1)}, v3{math.Inf(-1), math.Inf(-1), math.Inf(-1)}
		for _, t := range lt {
			for _, p := range t.p {
				lo = v3{math.Min(lo.x, p.x), math.Min(lo.y, p.y), math.Min(lo.z, p.z)}
				hi = v3{math.Max(hi.x, p.x), math.Max(hi.y, p.y), math.Max(hi.z, p.z)}
			}
		}
		log.Printf("LOD2 box: %v … %v", lo, hi)
	}
	log.Printf("LOD2: %d triangles, %d charts, %.0f m²", len(lt), len(charts), totalArea)

	// Texel density: shelf packing, shrinking until everything fits.
	S := *size
	const pad = 2
	d := math.Sqrt(*fill * float64(S*S) / totalArea)
	order := make([]*chart, len(charts))
	copy(order, charts)
	for {
		for _, c := range charts {
			c.w = int(math.Ceil((c.u1-c.u0)*d)) + 2*pad
			c.h = int(math.Ceil((c.v1-c.v0)*d)) + 2*pad
		}
		sort.Slice(order, func(i, j int) bool { return order[i].h > order[j].h })
		x, y, sh, ok := 0, 0, 0, true
		for _, c := range order {
			if c.w > S {
				ok = false
				break
			}
			if x+c.w > S {
				x, y, sh = 0, y+sh, 0
			}
			c.x, c.y = x, y
			x += c.w
			sh = max(sh, c.h)
			if y+c.h > S {
				ok = false
				break
			}
		}
		if ok {
			break
		}
		d *= 0.96
	}
	log.Printf("texel density %.1f px/m (%.1f cm/px)", d, 100/d)

	// Bake: every texel of every chart rectangle (padding included) casts a ray from outside
	// towards the plane; first hit within reach wins.
	atlas := image.NewRGBA(image.Rect(0, 0, S, S))
	have := make([]bool, S*S)
	const reach, depth = 2.0, 3.0
	var hits, misses int
	var offs []float64
	for _, c := range charts {
		for py := 0; py < c.h; py++ {
			for px := 0; px < c.w; px++ {
				u := c.u0 + (float64(px-pad)+0.5)/d
				v := c.v0 + (float64(py-pad)+0.5)/d
				p := c.o.add(c.t.mul(u)).add(c.b.mul(v))
				org := p.add(c.n.mul(reach))
				h, ok := bvh.hit(org, c.n.mul(-1), reach+depth)
				if !ok {
					misses++
					continue
				}
				hits++
				if px%7 == 0 && py%7 == 0 {
					offs = append(offs, reach-h.t)
				}
				col := sample(texs[h.tri.tex], h.uv)
				if *gain != 1 {
					g := func(c uint8) uint8 { return uint8(math.Min(255, float64(c)**gain+0.5)) }
					col = color.RGBA{g(col.R), g(col.G), g(col.B), 255}
				}
				ix, iy := c.x+px, S-1-(c.y+py) // v grows up, image rows down
				atlas.SetRGBA(ix, iy, col)
				have[iy*S+ix] = true
			}
		}
	}
	sort.Float64s(offs)
	log.Printf("bake: %d hits, %d misses", hits, misses)
	if len(offs) > 0 {
		log.Printf("bake: %d hits, %d misses; signed offset LOD2 → photo mesh p10 %.2f p50 %.2f p90 %.2f m (positive = photo inside)",
			hits, misses, offs[len(offs)/10], offs[len(offs)/2], offs[len(offs)*9/10])
	}
	dilate(atlas, have, S, 6)
	// Texels no ray reached (behind ornaments, gaps between charts): the mean photo colour, so
	// neither the surface nor the mip levels go black.
	var sr, sg, sb, sn int
	for i, h := range have {
		if h {
			c := atlas.RGBAAt(i%S, i/S)
			sr, sg, sb, sn = sr+int(c.R), sg+int(c.G), sb+int(c.B), sn+1
		}
	}
	if sn > 0 {
		mean := color.RGBA{uint8(sr / sn), uint8(sg / sn), uint8(sb / sn), 255}
		for i, h := range have {
			if !h {
				atlas.SetRGBA(i%S, i/S, mean)
			}
		}
		log.Printf("filled %d texels with the mean %v", S*S-sn, mean)
	}

	if err := os.MkdirAll(*out, 0o755); err != nil {
		log.Fatal(err)
	}
	jpgPath := filepath.Join(*out, fmt.Sprintf("atlas_%d.jpg", S))
	f, err := os.Create(jpgPath)
	if err != nil {
		log.Fatal(err)
	}
	if err := jpeg.Encode(f, atlas, &jpeg.Options{Quality: 85}); err != nil {
		log.Fatal(err)
	}
	f.Close()

	// UVs per triangle corner (u right, v up, 0…65535).
	type partOut struct {
		Part int `json:"part"`
		Tris int `json:"tris"`
	}
	meta := struct {
		Model    string    `json:"model"`
		Building string    `json:"building"`
		Size     int       `json:"size"`
		Atlas    string    `json:"atlas"`
		DensityM float64   `json:"px_per_m"`
		Parts    []partOut `json:"parts"`
		Credit   string    `json:"credit"`
	}{Model: *model, Building: *bid, Size: S, Atlas: filepath.Base(jpgPath), DensityM: d,
		Credit: "Fotorealistický 3D model Prahy © IPR Praha (CC BY 4.0)"}
	var uv []uint16
	cur := -1
	for _, t := range lt {
		if t.part != cur {
			meta.Parts = append(meta.Parts, partOut{Part: t.part})
			cur = t.part
		}
		meta.Parts[len(meta.Parts)-1].Tris++
		c := charts[t.chart]
		for _, p := range t.p {
			u := (p.sub(c.o).dot(c.t)-c.u0)*d + pad + float64(c.x)
			v := (p.sub(c.o).dot(c.b)-c.v0)*d + pad + float64(c.y)
			uv = append(uv, q16(u/float64(S)), q16(v/float64(S)))
		}
	}
	bf, err := os.Create(filepath.Join(*out, "uv.bin"))
	if err != nil {
		log.Fatal(err)
	}
	binary.Write(bf, binary.LittleEndian, uv)
	bf.Close()
	mj, _ := json.MarshalIndent(meta, "", "  ")
	os.WriteFile(filepath.Join(*out, "photo.json"), mj, 0o644)
	log.Printf("wrote %s, uv.bin (%d B), photo.json", jpgPath, 2*len(uv))
}

func q16(x float64) uint16 { return uint16(math.Round(math.Max(0, math.Min(1, x)) * 65535)) }

func mustProto(path string, m proto.Message) {
	f, err := os.Open(path)
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()
	zr, err := gzip.NewReader(f)
	if err != nil {
		log.Fatal(err)
	}
	b, err := io.ReadAll(zr)
	if err != nil {
		log.Fatal(err)
	}
	if err := proto.Unmarshal(b, m); err != nil {
		log.Fatal(err)
	}
}

func readBuilding(path, id string) *citygml.Building {
	f, err := os.Open(path)
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()
	var got *citygml.Building
	err = citygml.Read(f, func(v citygml.V3) citygml.V3 { return v }, func(float64, float64, float64, float64) bool { return true },
		func(b *citygml.Building) error {
			if b.ID == id {
				got = b
			}
			return nil
		})
	if err != nil || got == nil {
		log.Fatalf("building %s: %v", id, err)
	}
	return got
}

func groundPlane(gv []citygml.V3) ([3]float64, bool) {
	if len(gv) < 3 {
		return [3]float64{}, false
	}
	var mx, my, mz float64
	for _, v := range gv {
		mx, my, mz = mx+v.X, my+v.Y, mz+v.Z
	}
	n := float64(len(gv))
	mx, my, mz = mx/n, my/n, mz/n
	var sxx, sxy, syy, sxz, syz float64
	for _, v := range gv {
		x, y, z := v.X-mx, v.Y-my, v.Z-mz
		sxx, sxy, syy, sxz, syz = sxx+x*x, sxy+x*y, syy+y*y, sxz+x*z, syz+y*z
	}
	det := sxx*syy - sxy*sxy
	if math.Abs(det) < 1e-6 {
		return [3]float64{mz, 0, 0}, true
	}
	b := (sxz*syy - syz*sxy) / det
	c := (syz*sxx - sxz*sxy) / det
	return [3]float64{mz - b*mx - c*my, b, c}, true
}

// quad: source x, y → local metres, a quadratic fitted to PROJ through WGS84 (as models v3).
type quad struct {
	cx, cy, s float64
	kx, ky    [6]float64
}

func (t quad) terms(p geo.Pt) [6]float64 {
	u, v := (p.X-t.cx)/t.s, (p.Y-t.cy)/t.s
	return [6]float64{1, u, v, u * u, u * v, v * v}
}

func (t quad) apply(p geo.Pt) geo.Pt {
	w := t.terms(p)
	var x, y float64
	for i := range w {
		x, y = x+t.kx[i]*w[i], y+t.ky[i]*w[i]
	}
	return geo.Pt{X: x, Y: y}
}

func fitQuad(srs string, x1, y1, x2, y2 float64, proj geo.Projection) quad {
	const n = 5
	var src []geo.Pt
	var vals []string
	for i := 0; i < n; i++ {
		for j := 0; j < n; j++ {
			p := geo.Pt{X: x1 + (x2-x1)*float64(i)/(n-1), Y: y1 + (y2-y1)*float64(j)/(n-1)}
			src = append(src, p)
			vals = append(vals, fmt.Sprintf("(%d, %.3f, %.3f)", len(src)-1, p.X, p.Y))
		}
	}
	rows, err := duck.Query("phototrial quad", "", fmt.Sprintf(
		"SELECT i, ST_X(g) AS x, ST_Y(g) AS y FROM (SELECT i, ST_Transform(ST_Point(x, y), %s, 'EPSG:4326') AS g FROM (VALUES %s) t(i, x, y)) ORDER BY i",
		duck.Quote(srs), strings.Join(vals, ", ")))
	if err != nil || len(rows) != len(src) {
		log.Fatalf("quad: %v (%d rows)", err, len(rows))
	}
	dst := make([]geo.Pt, len(rows))
	for k, r := range rows {
		lon, _ := strconv.ParseFloat(r[1], 64)
		lat, _ := strconv.ParseFloat(r[2], 64)
		dst[k] = proj.Forward(lon, lat)
	}
	t := quad{cx: (x1 + x2) / 2, cy: (y1 + y2) / 2, s: math.Max(x2-x1, y2-y1) / 2}
	var ata [6][6]float64
	var bx, by [6]float64
	for k, p := range src {
		w := t.terms(p)
		for i := 0; i < 6; i++ {
			for j := 0; j < 6; j++ {
				ata[i][j] += w[i] * w[j]
			}
			bx[i] += w[i] * dst[k].X
			by[i] += w[i] * dst[k].Y
		}
	}
	t.kx, t.ky = solve6(ata, bx), solve6(ata, by)
	res := 0.0
	for k, p := range src {
		res = math.Max(res, t.apply(p).Dist(dst[k]))
	}
	log.Printf("quad residual %.4f m", res)
	return t
}

func solve6(a [6][6]float64, b [6]float64) [6]float64 {
	for c := 0; c < 6; c++ {
		p := c
		for r := c + 1; r < 6; r++ {
			if math.Abs(a[r][c]) > math.Abs(a[p][c]) {
				p = r
			}
		}
		a[c], a[p] = a[p], a[c]
		b[c], b[p] = b[p], b[c]
		for r := 0; r < 6; r++ {
			if r == c {
				continue
			}
			f := a[r][c] / a[c][c]
			for k := c; k < 6; k++ {
				a[r][k] -= f * a[c][k]
			}
			b[r] -= f * b[c]
		}
	}
	var x [6]float64
	for i := range x {
		x[i] = b[i] / a[i][i]
	}
	return x
}

// Photo mesh.
type mtri struct {
	p   [3]v3
	uv  [3][2]float64
	tex int
}

func objBox(path string) (x1, y1, x2, y2 float64) {
	f, err := os.Open(path)
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()
	x1, y1, x2, y2 = math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	for sc.Scan() {
		l := sc.Text()
		if !strings.HasPrefix(l, "v ") {
			continue
		}
		fs := strings.Fields(l)
		x, _ := strconv.ParseFloat(fs[1], 64)
		y, _ := strconv.ParseFloat(fs[2], 64)
		x1, y1, x2, y2 = math.Min(x1, x), math.Min(y1, y), math.Max(x2, x), math.Max(y2, y)
	}
	return
}

func readOBJ(path string, tex int, x1, y1, x2, y2 float64, to func(x, y, z float64) v3, out []mtri) []mtri {
	f, err := os.Open(path)
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()
	var vs [][3]float64
	var vt [][2]float64
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	idx := func(s string, n int) int {
		i, _ := strconv.Atoi(s)
		if i < 0 {
			return n + i
		}
		return i - 1
	}
	for sc.Scan() {
		l := sc.Text()
		switch {
		case strings.HasPrefix(l, "v "):
			fs := strings.Fields(l)
			x, _ := strconv.ParseFloat(fs[1], 64)
			y, _ := strconv.ParseFloat(fs[2], 64)
			z, _ := strconv.ParseFloat(fs[3], 64)
			vs = append(vs, [3]float64{x, y, z})
		case strings.HasPrefix(l, "vt "):
			fs := strings.Fields(l)
			u, _ := strconv.ParseFloat(fs[1], 64)
			v, _ := strconv.ParseFloat(fs[2], 64)
			vt = append(vt, [2]float64{u, v})
		case strings.HasPrefix(l, "f "):
			fs := strings.Fields(l)[1:]
			var pi, ti []int
			for _, c := range fs {
				parts := strings.Split(c, "/")
				pi = append(pi, idx(parts[0], len(vs)))
				if len(parts) > 1 && parts[1] != "" {
					ti = append(ti, idx(parts[1], len(vt)))
				} else {
					ti = append(ti, -1)
				}
			}
			for k := 1; k+1 < len(pi); k++ {
				ids := [3]int{0, k, k + 1}
				in := false
				for _, j := range ids {
					p := vs[pi[j]]
					if p[0] >= x1 && p[0] <= x2 && p[1] >= y1 && p[1] <= y2 {
						in = true
					}
				}
				if !in {
					continue
				}
				var t mtri
				t.tex = tex
				for c, j := range ids {
					p := vs[pi[j]]
					t.p[c] = to(p[0], p[1], p[2])
					if ti[j] >= 0 {
						t.uv[c] = vt[ti[j]]
					}
				}
				out = append(out, t)
			}
		}
	}
	return out
}

func mustJPEG(path string) image.Image {
	f, err := os.Open(path)
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()
	img, err := jpeg.Decode(f)
	if err != nil {
		log.Fatalf("%s: %v", path, err)
	}
	return img
}

func sample(img image.Image, uv [2]float64) color.RGBA {
	b := img.Bounds()
	w, h := float64(b.Dx()), float64(b.Dy())
	x := uv[0]*w - 0.5
	y := (1-uv[1])*h - 0.5
	x0, y0 := math.Floor(x), math.Floor(y)
	fx, fy := x-x0, y-y0
	var acc [3]float64
	for j := 0; j < 2; j++ {
		for i := 0; i < 2; i++ {
			px := min(max(int(x0)+i, 0), b.Dx()-1) + b.Min.X
			py := min(max(int(y0)+j, 0), b.Dy()-1) + b.Min.Y
			r, g, bb, _ := img.At(px, py).RGBA()
			wt := (1 - math.Abs(float64(i)-fx)) * (1 - math.Abs(float64(j)-fy))
			acc[0] += wt * float64(r>>8)
			acc[1] += wt * float64(g>>8)
			acc[2] += wt * float64(bb>>8)
		}
	}
	return color.RGBA{uint8(acc[0] + 0.5), uint8(acc[1] + 0.5), uint8(acc[2] + 0.5), 255}
}

func dilate(img *image.RGBA, have []bool, S, n int) {
	for it := 0; it < n; it++ {
		next := append([]bool(nil), have...)
		for y := 0; y < S; y++ {
			for x := 0; x < S; x++ {
				if have[y*S+x] {
					continue
				}
				var r, g, b, k int
				for _, d := range [][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}} {
					xx, yy := x+d[0], y+d[1]
					if xx < 0 || yy < 0 || xx >= S || yy >= S || !have[yy*S+xx] {
						continue
					}
					c := img.RGBAAt(xx, yy)
					r, g, b, k = r+int(c.R), g+int(c.G), b+int(c.B), k+1
				}
				if k > 0 {
					img.SetRGBA(x, y, color.RGBA{uint8(r / k), uint8(g / k), uint8(b / k), 255})
					next[y*S+x] = true
				}
			}
		}
		copy(have, next)
	}
}

// BVH over the photo mesh.
type node struct {
	lo, hi      v3
	left, right int // children (inner) or -1
	start, n    int // triangle range (leaf)
}

type bvh struct {
	nodes []node
	tris  []mtri
}

type hitT struct {
	t   float64
	uv  [2]float64
	tri *mtri
}

func buildBVH(ts []mtri) *bvh {
	b := &bvh{tris: ts}
	var build func(s, e int) int
	build = func(s, e int) int {
		lo, hi := v3{math.Inf(1), math.Inf(1), math.Inf(1)}, v3{math.Inf(-1), math.Inf(-1), math.Inf(-1)}
		for _, t := range ts[s:e] {
			for _, p := range t.p {
				lo = v3{math.Min(lo.x, p.x), math.Min(lo.y, p.y), math.Min(lo.z, p.z)}
				hi = v3{math.Max(hi.x, p.x), math.Max(hi.y, p.y), math.Max(hi.z, p.z)}
			}
		}
		i := len(b.nodes)
		b.nodes = append(b.nodes, node{lo: lo, hi: hi, left: -1, right: -1, start: s, n: e - s})
		if e-s <= 6 {
			return i
		}
		ext := hi.sub(lo)
		axis := 0
		if ext.y > ext.x && ext.y >= ext.z {
			axis = 1
		} else if ext.z > ext.x && ext.z > ext.y {
			axis = 2
		}
		c := func(t mtri) float64 {
			switch axis {
			case 0:
				return t.p[0].x + t.p[1].x + t.p[2].x
			case 1:
				return t.p[0].y + t.p[1].y + t.p[2].y
			}
			return t.p[0].z + t.p[1].z + t.p[2].z
		}
		sub := ts[s:e]
		sort.Slice(sub, func(i, j int) bool { return c(sub[i]) < c(sub[j]) })
		mid := (s + e) / 2
		l := build(s, mid)
		r := build(mid, e)
		b.nodes[i].left, b.nodes[i].right = l, r
		return i
	}
	build(0, len(ts))
	return b
}

func (b *bvh) hit(o, d v3, tmax float64) (hitT, bool) {
	best := hitT{t: tmax}
	found := false
	inv := v3{1 / d.x, 1 / d.y, 1 / d.z}
	stack := []int{0}
	for len(stack) > 0 {
		i := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		nd := &b.nodes[i]
		if !boxHit(o, inv, nd.lo, nd.hi, best.t) {
			continue
		}
		if nd.left < 0 {
			for k := nd.start; k < nd.start+nd.n; k++ {
				t := &b.tris[k]
				if tt, u, v, ok := triHit(o, d, t); ok && tt > 0 && tt < best.t {
					w := 1 - u - v
					best = hitT{t: tt, tri: t, uv: [2]float64{
						w*t.uv[0][0] + u*t.uv[1][0] + v*t.uv[2][0],
						w*t.uv[0][1] + u*t.uv[1][1] + v*t.uv[2][1]}}
					found = true
				}
			}
			continue
		}
		stack = append(stack, nd.left, nd.right)
	}
	return best, found
}

func boxHit(o, inv, lo, hi v3, tmax float64) bool {
	t0, t1 := 0.0, tmax
	for a := 0; a < 3; a++ {
		var oo, ii, l, h float64
		switch a {
		case 0:
			oo, ii, l, h = o.x, inv.x, lo.x, hi.x
		case 1:
			oo, ii, l, h = o.y, inv.y, lo.y, hi.y
		default:
			oo, ii, l, h = o.z, inv.z, lo.z, hi.z
		}
		ta, tb := (l-oo)*ii, (h-oo)*ii
		if ta > tb {
			ta, tb = tb, ta
		}
		if math.IsNaN(ta) || math.IsNaN(tb) {
			if oo < l || oo > h {
				return false
			}
			continue
		}
		t0, t1 = math.Max(t0, ta), math.Min(t1, tb)
		if t0 > t1 {
			return false
		}
	}
	return true
}

func triHit(o, d v3, t *mtri) (float64, float64, float64, bool) {
	e1, e2 := t.p[1].sub(t.p[0]), t.p[2].sub(t.p[0])
	p := d.cross(e2)
	det := e1.dot(p)
	if math.Abs(det) < 1e-12 {
		return 0, 0, 0, false
	}
	inv := 1 / det
	s := o.sub(t.p[0])
	u := s.dot(p) * inv
	if u < 0 || u > 1 {
		return 0, 0, 0, false
	}
	q := s.cross(e1)
	v := d.dot(q) * inv
	if v < 0 || u+v > 1 {
		return 0, 0, 0, false
	}
	return e2.dot(q) * inv, u, v, true
}
