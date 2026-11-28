package steps

import (
	"fmt"
	"log/slog"
	"math"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strconv"
	"strings"

	"citypack/internal/citygml"
	"citypack/internal/config"
	"citypack/internal/duck"
	"citypack/internal/geo"
	"citypack/internal/pb"
)

// ModelsVersion is Manifest.models_version (specs/models.md).
const ModelsVersion = 2

// modelSources maps models.yaml `source` to the enum and the attribution line (plan H9).
var modelSources = map[string]struct {
	src  pb.ModelSource
	attr string
	srs  string // CRS of the source coordinates (DuckDB / PROJ name)
	// v5: latLon = geographic source, x = latitude, y = longitude in degrees (PLATEAU EPSG:6697,
	// JGD2011 + T.P. height); projected straight with the pack projection, no PROJ fit.
	latLon bool
	lod    int // citygml.ReadLOD: the LOD kept per building (0 = the highest)
	// v6: zScale converts source heights to metres (0 = already metres). NYC: US survey feet.
	zScale float64
}{
	"ipr_praha_3d": {pb.ModelSource_MODEL_SOURCE_IPR_PRAHA_3D, "3D model: data base © IPR Praha (CC BY 4.0)", "EPSG:5514", false, -1, 0},
	// PDL 1.0 (CC BY 4.0 compatible); edited data must say so (docs/citypack.md, NOTICE).
	"plateau": {pb.ModelSource_MODEL_SOURCE_PLATEAU,
		"3D model: Source: MLIT Project PLATEAU (https://www.mlit.go.jp/plateau/open-data/), processed (PDL 1.0)", "EPSG:6697", true, 2, 0},
	// v6: NYC OTI (DoITT) 3-D Building Massing Model, CityGML LOD2 per delivery area, NAD83 /
	// New York Long Island ftUS (EPSG:2263), heights NAVD88 in US survey feet. NYC Open Data has
	// no use restrictions (Admin. Code § 23-502(d)); a republisher names source, version and
	// modifications, so the line does too (docs/citypack.md, NOTICE).
	"nyc_3d": {pb.ModelSource_MODEL_SOURCE_NYC_3D,
		"3D model: NYC 3-D Building Massing Model, NYC OTI (NYC Open Data tnru-abg2, 2014 survey, published 2016-04-18), simplified and recoloured",
		"EPSG:2263", false, 2, usFootM},
}

// usFootM is one US survey foot in metres (1200/3937).
const usFootM = 1200.0 / 3937.0

// ModelAttribution is the manifest line of a model source.
func ModelAttribution(s pb.ModelSource) string {
	for _, v := range modelSources {
		if v.src == s {
			return v.attr
		}
	}
	return ""
}

const towerUsage = "vyznacna vez na strese" // IPR: a marked tower on the roof → copper roof

var roleNames = map[string]pb.ModelRole{
	"wall": pb.ModelRole_ROLE_WALL, "roof": pb.ModelRole_ROLE_ROOF, "copper": pb.ModelRole_ROLE_COPPER,
	"stone": pb.ModelRole_ROLE_STONE, "glass": pb.ModelRole_ROLE_GLASS, "gold": pb.ModelRole_ROLE_GOLD,
	"slate": pb.ModelRole_ROLE_SLATE,
}

// copperRule is tuning `models.copper_*` (specs/models.md v2 "Role"): a part (not an installation)
// whose top is at least minTop above the foot and whose footprint (larger side of its box) is at
// most slender × its own height has copper roofs. Zero values switch the rule off.
// v4 adds the part rules of tuning `models.ground_float_m` and `models.part_box_slack_m`.
type copperRule struct{ minTop, slender, groundFloat, boxSlack float64 }

func (c copperRule) slenderPart(top, height, footprint float64, installation bool) bool {
	return !installation && c.minTop > 0 && top >= c.minTop && footprint <= c.slender*height
}

// surfaceRole is the role of a polygon (specs/models.md v2 "Role"). Walls: `wall`, then
// models.yaml `walls` by building id, then by part id. Roofs: `roof`, then `roles` by building id,
// then copper for marked towers (IPR usage) and slender tall parts (v3: `towers` by building id
// instead of copper), then `roles` by part id.
func surfaceRole(kind citygml.Kind, mc config.ModelConfig, buildingID, partID string, tower, slender bool) pb.ModelRole {
	over := mc.Walls
	role := pb.ModelRole_ROLE_WALL
	if kind == citygml.Roof {
		over, role = mc.Roles, pb.ModelRole_ROLE_ROOF
	}
	if r, ok := roleNames[over[buildingID]]; ok && buildingID != "" {
		role = r
	}
	if kind == citygml.Roof && (tower || slender) {
		role = pb.ModelRole_ROLE_COPPER
		if r, ok := roleNames[mc.Towers[buildingID]]; ok && buildingID != "" {
			role = r
		}
	}
	if r, ok := roleNames[over[partID]]; ok && partID != "" && partID != buildingID {
		role = r
	}
	return role
}

// Models builds models.pb from content/cities/<id>/models.yaml (specs/models.md, plan ch. 6).
// It runs after landmarks and elevation; pack resolves `replaces` and copies the file.
func Models(e *Env) error {
	out := e.W("models.pb")
	mf := e.C.Models
	if mf == nil || !e.C.Tuning.Models.Enabled || len(mf.Models) == 0 {
		_ = os.Remove(out)
		slog.Info("models: none configured")
		return nil
	}
	if e.fresh(out) {
		skip("models", out)
		return nil
	}
	src, ok := modelSources[mf.Source]
	if !ok {
		return fmt.Errorf("models.yaml: unsupported source %q", mf.Source)
	}
	masses, err := e.LoadMasses()
	if err != nil {
		return err
	}
	tg, elev, err := e.LoadTerrain()
	if err != nil {
		return err
	}
	ids := make([]string, 0, len(mf.Models))
	for id := range mf.Models {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	sels := make([]*modelSelection, len(ids))
	for i, id := range ids {
		if sels[i], err = e.selection(id, mf.Models[id], masses); err != nil {
			return err
		}
	}
	files := mf.Files
	if len(files) == 0 {
		files, _ = filepath.Glob(filepath.Join(e.Work, "raw", "models", "*.gml"))
	} else {
		for i, f := range files {
			files[i] = filepath.Join(e.Work, "raw", "models", f)
		}
	}
	if len(files) == 0 {
		return fmt.Errorf("models: no source files in %s (see docs/citypack.md, IPR Praha 3D model)", filepath.Join(e.Work, "raw", "models"))
	}
	picked := make([][]*srcBuilding, len(ids))
	// v3 "Mosty": bridges come from their own shapefile; the selection box grows over them so
	// `include` reaches buildings at the far end (the towers of a bridge).
	for i, id := range ids {
		bs, err := e.readBridges(mf.Models[id], src.srs)
		if err != nil {
			return fmt.Errorf("models %s: %w", id, err)
		}
		for _, b := range bs {
			for _, p := range b.Polys {
				for _, v := range p.Rings[0] {
					s := sels[i]
					s.minX, s.maxX = math.Min(s.minX, v.X), math.Max(s.maxX, v.X)
					s.minY, s.maxY = math.Min(s.minY, v.Y), math.Max(s.maxY, v.Y)
				}
			}
		}
		picked[i] = append(picked[i], bs...)
	}
	for _, f := range files {
		bs, err := e.readSource(f, src.srs, src.latLon, src.lod, src.zScale, sels)
		if err != nil {
			return err
		}
		for _, b := range bs {
			for i, s := range sels {
				if s.wants(b) {
					picked[i] = append(picked[i], b)
				}
			}
		}
	}
	mt := e.C.Tuning.Models
	exag := 1.0
	if elev != nil && elev.Exaggeration > 0 {
		exag = elev.Exaggeration
	}
	res := &pb.Models{}
	total := 0
	for i, id := range ids {
		mc := mf.Models[id]
		budget := mt.MaxTris
		if mc.MaxTris > 0 {
			if mc.MaxTris > mt.MaxTrisException {
				return fmt.Errorf("models.yaml %s: max_tris %d over models.max_tris_exception %d", id, mc.MaxTris, mt.MaxTrisException)
			}
			budget = mc.MaxTris
		}
		if len(picked[i]) == 0 {
			return fmt.Errorf("models %s: no source buildings selected", id)
		}
		if len(mc.Drop) > 0 {
			picked[i] = e.dropPolys(id, picked[i], mc.Drop)
		}
		for k := range mc.Parts {
			lp := e.Proj.Forward(mc.Parts[k].At[0], mc.Parts[k].At[1])
			mc.Parts[k].XY = [2]float64{lp.X, lp.Y}
		}
		var m *pb.Model
		detail := mt.MinDetailM
		for {
			m = buildModel(picked[i], mc, detail, mt, tg, exag)
			if int(m.Tris) <= budget {
				break
			}
			if detail+1e-9 >= mt.MaxDetailM {
				return fmt.Errorf("models %s: %d triangles at min_detail %.1f m, %d over max_tris %d; exclude parts in models.yaml",
					id, m.Tris, detail, int(m.Tris)-budget, budget)
			}
			detail = math.Min(mt.MaxDetailM, detail+mt.DetailStepM)
		}
		m.LandmarkId, m.Source = id, src.src
		// v3: the part nearest to the landmark point goes first (clients build the mesh with the
		// chunk of the first part's anchor; a bridge's far tower must not wait for its chunk).
		for _, l := range e.C.Landmarks {
			if l.ID == id {
				lp := e.Proj.Forward(l.Lon, l.Lat)
				d := func(p *pb.ModelPart) float64 {
					return geo.Pt{X: float64(p.AnchorX) / 10, Y: float64(p.AnchorY) / 10}.Dist(lp)
				}
				sort.SliceStable(m.Parts, func(i, j int) bool { return d(m.Parts[i]) < d(m.Parts[j]) })
			}
		}
		total += int(m.Tris)
		res.Models = append(res.Models, m)
		slog.Info("models: built", "id", id, "buildings", len(m.Parts), "tris", m.Tris, "plan_polys", len(m.RoofPlan),
			"min_detail_m", detail, "source", mf.Source)
		if err := e.previewModel(m, exag); err != nil {
			slog.Warn("models: preview failed", "id", id, "err", err)
		}
	}
	if total > mt.CityMaxTris {
		return fmt.Errorf("models: %d triangles over models.city_max_tris %d", total, mt.CityMaxTris)
	}
	return writePB(out, res, false)
}

// dropPolys removes the source polygons whose vertex mean lies inside a models.yaml `drop` ring
// (v6; a wall shared with the kept building lies on the ring's edge and stays). The
// buildings are copied: another model may hold the same source building.
func (e *Env) dropPolys(id string, bs []*srcBuilding, drop [][][2]float64) []*srcBuilding {
	rings := make([][]geo.Pt, len(drop))
	for k, r := range drop {
		for _, ll := range r {
			rings[k] = append(rings[k], e.Proj.Forward(ll[0], ll[1]))
		}
	}
	out := make([]*srcBuilding, 0, len(bs))
	n := 0
	for _, b := range bs {
		c := *b
		c.Polys = make([]citygml.Poly, 0, len(b.Polys))
		for _, p := range b.Polys {
			if polyInside(p, rings) {
				n++
				continue
			}
			c.Polys = append(c.Polys, p)
		}
		out = append(out, &c)
	}
	slog.Info("models: dropped polygons", "id", id, "polys", n)
	return out
}

func polyInside(p citygml.Poly, rings [][]geo.Pt) bool {
	var c geo.Pt
	for _, v := range p.Rings[0] {
		c.X, c.Y = c.X+v.X, c.Y+v.Y
	}
	c.X, c.Y = c.X/float64(len(p.Rings[0])), c.Y/float64(len(p.Rings[0]))
	for _, r := range rings {
		if len(r) >= 3 && geo.PointInRing(c, r) {
			return true
		}
	}
	return false
}

type srcBuilding struct {
	Bridge bool // v3: a bridge of the IPR "Mosty 3D" set (buildBridgePart)
	ID     string
	Groups []citygml.Group
	Polys  []citygml.Poly // local metres, z real
	C      geo.Pt         // centroid of the ground footprint (all vertices without one)
}

type modelSelection struct {
	id                     string
	area                   []geo.Pt
	lm                     [][]geo.Pt // landmark footprints (outer rings)
	buffer                 float64
	include                map[string]bool
	exclude                map[string]bool
	minX, minY, maxX, maxY float64
}

func (e *Env) selection(id string, mc config.ModelConfig, masses []MassRow) (*modelSelection, error) {
	idx := -1
	for i, l := range e.C.Landmarks {
		if l.ID == id {
			idx = i + 1
		}
	}
	if idx < 0 {
		return nil, fmt.Errorf("models.yaml: %s is not in landmarks.yaml", id)
	}
	s := &modelSelection{id: id, buffer: mc.Select.BufferM, include: map[string]bool{}, exclude: map[string]bool{},
		minX: math.Inf(1), minY: math.Inf(1), maxX: math.Inf(-1), maxY: math.Inf(-1)}
	grow := func(p geo.Pt, r float64) {
		s.minX, s.maxX = math.Min(s.minX, p.X-r), math.Max(s.maxX, p.X+r)
		s.minY, s.maxY = math.Min(s.minY, p.Y-r), math.Max(s.maxY, p.Y+r)
	}
	for _, m := range masses {
		if m.Landmark == idx && len(m.Rings) > 0 {
			s.lm = append(s.lm, m.Rings[0])
			for _, p := range m.Rings[0] {
				grow(p, s.buffer)
			}
		}
	}
	for _, ll := range mc.Select.Area {
		p := e.Proj.Forward(ll[0], ll[1])
		s.area = append(s.area, p)
		grow(p, 0)
	}
	if len(s.lm) == 0 && len(s.area) == 0 {
		if len(mc.Include) == 0 {
			return nil, fmt.Errorf("models %s: the landmark has no building and models.yaml neither select.area nor include", id)
		}
		// v5: a plaza landmark (Kaminarimon) picks its source buildings by id only; read the
		// source as far as validate lets the model reach.
		l := e.C.Landmarks[idx-1]
		r := e.C.Tuning.Models.MaxOffsetM
		if mc.MaxOffsetM > 0 {
			r = min(mc.MaxOffsetM, e.C.Tuning.Models.NearM)
		}
		grow(e.Proj.Forward(l.Lon, l.Lat), r)
	}
	for _, x := range mc.Include {
		s.include[x] = true
	}
	for _, x := range mc.Exclude {
		s.exclude[x] = true
	}
	return s, nil
}

func (s *modelSelection) wants(b *srcBuilding) bool {
	if s.exclude[b.ID] {
		return false
	}
	if s.include[b.ID] {
		return true
	}
	if len(s.area) >= 3 && geo.PointInRing(b.C, s.area) {
		return true
	}
	for _, r := range s.lm {
		if geo.PointInRing(b.C, r) || distToRing(b.C, r) <= s.buffer {
			return true
		}
	}
	return false
}

func distToRing(p geo.Pt, r []geo.Pt) float64 {
	d := math.Inf(1)
	for i := range r {
		q, _ := geo.ClosestOnSegment(p, r[i], r[(i+1)%len(r)])
		d = math.Min(d, q.Dist(p))
	}
	return d
}

// readSource streams one source file and keeps the buildings near any selection.
func (e *Env) readSource(path, srs string, latLon bool, lod int, zScale float64, sels []*modelSelection) ([]*srcBuilding, error) {
	if zScale == 0 {
		zScale = 1
	}
	var af affine
	toLocal := func(p geo.Pt) geo.Pt { return e.Proj.Forward(p.Y, p.X) } // v5: latitude, longitude
	if !latLon {
		f, err := os.Open(path)
		if err != nil {
			return nil, err
		}
		x1, y1, x2, y2, err := citygml.Envelope(f)
		f.Close()
		if err != nil {
			return nil, fmt.Errorf("%s: %w", filepath.Base(path), err)
		}
		if af, err = e.fitAffine(srs, x1, y1, x2, y2); err != nil {
			return nil, err
		}
		toLocal = af.apply
	}
	near := func(minX, minY, maxX, maxY float64) bool {
		a := toLocal(geo.Pt{X: minX, Y: minY})
		b := toLocal(geo.Pt{X: maxX, Y: maxY})
		c := toLocal(geo.Pt{X: minX, Y: maxY})
		d := toLocal(geo.Pt{X: maxX, Y: minY})
		lx, hx := math.Min(math.Min(a.X, b.X), math.Min(c.X, d.X)), math.Max(math.Max(a.X, b.X), math.Max(c.X, d.X))
		ly, hy := math.Min(math.Min(a.Y, b.Y), math.Min(c.Y, d.Y)), math.Max(math.Max(a.Y, b.Y), math.Max(c.Y, d.Y))
		for _, s := range sels {
			if hx >= s.minX-50 && lx <= s.maxX+50 && hy >= s.minY-50 && ly <= s.maxY+50 {
				return true
			}
		}
		return false
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var out []*srcBuilding
	tf := func(v citygml.V3) citygml.V3 {
		p := toLocal(geo.Pt{X: v.X, Y: v.Y})
		return citygml.V3{X: p.X, Y: p.Y, Z: v.Z * zScale}
	}
	err = citygml.ReadLOD(f, lod, tf, near, func(b *citygml.Building) error {
		sb := &srcBuilding{ID: b.ID, Groups: b.Groups, Polys: b.Polys}
		var sx, sy float64
		n := 0
		for pass := 0; pass < 2 && n == 0; pass++ {
			for _, p := range b.Polys {
				if pass == 0 && p.Kind != citygml.Ground {
					continue
				}
				for _, v := range p.Rings[0] {
					sx, sy, n = sx+v.X, sy+v.Y, n+1
				}
			}
		}
		sb.C = geo.Pt{X: sx / float64(n), Y: sy / float64(n)}
		out = append(out, sb)
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("%s: %w", filepath.Base(path), err)
	}
	slog.Info("models: source read", "file", filepath.Base(path), "buildings_near", len(out), "affine_residual_m", fmt.Sprintf("%.3f", af.residual))
	return out, nil
}

// affine maps source x, y to local metres: a quadratic polynomial fitted to PROJ (DuckDB
// ST_Transform) on a grid over the source envelope (a 2.5 km sheet: residual well below 1 cm).
type affine struct {
	cx, cy, s float64    // centre and scale of the source coordinates (conditioning)
	kx, ky    [6]float64 // 1, u, v, u², uv, v²
	residual  float64
}

func (t affine) terms(p geo.Pt) [6]float64 {
	u, v := (p.X-t.cx)/t.s, (p.Y-t.cy)/t.s
	return [6]float64{1, u, v, u * u, u * v, v * v}
}

func (t affine) apply(p geo.Pt) geo.Pt {
	w := t.terms(p)
	var x, y float64
	for i := range w {
		x, y = x+t.kx[i]*w[i], y+t.ky[i]*w[i]
	}
	return geo.Pt{X: x, Y: y}
}

func (e *Env) fitAffine(srs string, x1, y1, x2, y2 float64) (affine, error) {
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
	// Through WGS84 (v3): a direct transform to the city's spherical projection has no datum and
	// PROJ falls back to a ballpark one that skips the S-JTSK → WGS84 shift (~117 m in Prague);
	// the pack projects WGS84 longitude and latitude (e.Proj), so the source must too.
	rows, err := duck.Query("models affine", "", fmt.Sprintf(
		"SELECT i, ST_X(g) AS x, ST_Y(g) AS y FROM (SELECT i, ST_Transform(ST_Point(x, y), %s, 'EPSG:4326') AS g FROM (VALUES %s) t(i, x, y)) ORDER BY i",
		duck.Quote(srs), strings.Join(vals, ", ")))
	if err != nil {
		return affine{}, err
	}
	if len(rows) != len(src) {
		return affine{}, fmt.Errorf("models affine: %d rows, want %d", len(rows), len(src))
	}
	dst := make([]geo.Pt, len(rows))
	for k, r := range rows {
		lon, _ := strconv.ParseFloat(r[1], 64)
		lat, _ := strconv.ParseFloat(r[2], 64)
		dst[k] = e.Proj.Forward(lon, lat)
	}
	return fitAffinePts(src, dst)
}

// fitAffinePts solves the least-squares quadratic transform src → dst.
func fitAffinePts(src, dst []geo.Pt) (affine, error) {
	t := affine{s: 1}
	x1, y1, x2, y2 := math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)
	for _, p := range src {
		x1, y1, x2, y2 = math.Min(x1, p.X), math.Min(y1, p.Y), math.Max(x2, p.X), math.Max(y2, p.Y)
	}
	t.cx, t.cy, t.s = (x1+x2)/2, (y1+y2)/2, math.Max(1, math.Max(x2-x1, y2-y1)/2)
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
	var ok bool
	if t.kx, ok = solve6(ata, bx); !ok {
		return t, fmt.Errorf("models affine: degenerate sample grid")
	}
	t.ky, _ = solve6(ata, by)
	for k, p := range src {
		t.residual = math.Max(t.residual, t.apply(p).Dist(dst[k]))
	}
	if t.residual > 0.05 {
		return t, fmt.Errorf("models affine: residual %.3f m over 0.05 m", t.residual)
	}
	return t, nil
}

// solve6 is Gaussian elimination with partial pivoting.
func solve6(a [6][6]float64, b [6]float64) ([6]float64, bool) {
	for c := 0; c < 6; c++ {
		p := c
		for r := c + 1; r < 6; r++ {
			if math.Abs(a[r][c]) > math.Abs(a[p][c]) {
				p = r
			}
		}
		if math.Abs(a[p][c]) < 1e-12 {
			return b, false
		}
		a[c], a[p] = a[p], a[c]
		b[c], b[p] = b[p], b[c]
		for r := c + 1; r < 6; r++ {
			f := a[r][c] / a[c][c]
			for k := c; k < 6; k++ {
				a[r][k] -= f * a[c][k]
			}
			b[r] -= f * b[c]
		}
	}
	var x [6]float64
	for r := 5; r >= 0; r-- {
		s := b[r]
		for k := r + 1; k < 6; k++ {
			s -= a[r][k] * x[k]
		}
		x[r] = s / a[r][r]
	}
	return x, true
}

// planSrc is one roof polygon kept for the roof plan.
type planSrc struct {
	rings [][]geo.Pt // absolute local metres
	shade uint32
	top   float64 // highest point above the foot
}

// buildModel turns the selected source buildings into one Model at the given detail.
func buildModel(bs []*srcBuilding, mc config.ModelConfig, detail float64, mt config.ModelsTuning, tg *TerrainGrid, exag float64) *pb.Model {
	sort.Slice(bs, func(i, j int) bool { return bs[i].ID < bs[j].ID })
	m := &pb.Model{}
	var plans [][]planSrc
	for _, b := range bs {
		var part *pb.ModelPart
		var plan []planSrc
		if b.Bridge {
			part, plan = buildBridgePart(b, mc, detail, mt.WeldM, mt.BridgeEndM, tg)
		} else {
			part, plan = buildPart(b, mc, copperRule{mt.CopperMinTopM, mt.CopperSlender, mt.GroundFloatM, mt.PartBoxSlackM}, detail, mt.WeldM, tg, exag)
		}
		if part == nil {
			continue
		}
		m.Parts = append(m.Parts, part)
		m.Tris += uint32(len(part.Roles))
		plans = append(plans, plan)
	}
	// The roof plan keeps four shades while it fits roof_plan_max_polys, else coarser.
	for coarse := 0; coarse < 3; coarse++ {
		m.RoofPlan = m.RoofPlan[:0]
		for i, part := range m.Parts {
			m.RoofPlan = append(m.RoofPlan, roofPlan(plans[i], part.BaseZDm, mt.PlanSimplifyM, coarse)...)
		}
		if len(m.RoofPlan) <= mt.RoofPlanMaxPolys {
			break
		}
		slog.Debug("models: roof plan too detailed", "polys", len(m.RoofPlan), "coarse", coarse)
	}
	if len(m.RoofPlan) > mt.RoofPlanMaxPolys {
		// Keep the largest polygons; the rest are below the plan's resolution anyway.
		sort.SliceStable(m.RoofPlan, func(i, j int) bool { return planArea(m.RoofPlan[i]) > planArea(m.RoofPlan[j]) })
		m.RoofPlan = m.RoofPlan[:mt.RoofPlanMaxPolys]
	}
	sort.SliceStable(m.RoofPlan, func(i, j int) bool { return m.RoofPlan[i].HeightM < m.RoofPlan[j].HeightM })
	return m
}

func planArea(p *pb.PlanPoly) float64 {
	end := len(p.Points) / 2
	if len(p.RingEnds) > 0 {
		end = int(p.RingEnds[0])
	}
	r := make([]geo.Pt, end)
	for i := range r {
		r[i] = geo.Pt{X: float64(p.Points[2*i]) / 10, Y: float64(p.Points[2*i+1]) / 10}
	}
	return math.Abs(geo.SignedArea(r))
}

type v3 struct{ x, y, z float64 }

func (a v3) sub(b v3) v3      { return v3{a.x - b.x, a.y - b.y, a.z - b.z} }
func (a v3) cross(b v3) v3    { return v3{a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x} }
func (a v3) dot(b v3) float64 { return a.x*b.x + a.y*b.y + a.z*b.z }
func (a v3) norm() float64    { return math.Sqrt(a.dot(a)) }

// sunDir is the fixed roof-plan light: azimuth 315°, altitude 45° (as the terrain shade).
var sunDir = v3{-0.5, 0.5, math.Sqrt2 / 2}

// roofShade buckets a roof normal against the fixed light (specs/models.md): 0 … 3.
func roofShade(n v3) uint32 {
	d := n.dot(sunDir) / n.norm()
	switch {
	case d < 0.25:
		return 0
	case d < 0.55:
		return 1
	case d < 0.85:
		return 2
	}
	return 3
}

func buildPart(b *srcBuilding, mc config.ModelConfig, cu copperRule, detail, weld float64, tg *TerrainGrid, exag float64) (*pb.ModelPart, []planSrc) {
	// Groups smaller than the detail go (chimneys, dormers, small installations).
	type box struct{ x1, y1, z1, x2, y2, z2 float64 }
	boxes := make([]box, len(b.Groups))
	for i := range boxes {
		boxes[i] = box{math.Inf(1), math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1), math.Inf(-1)}
	}
	foot, groundSeen := math.Inf(1), false
	allMin := math.Inf(1)
	for _, p := range b.Polys {
		bx := &boxes[p.Group]
		for _, v := range p.Rings[0] {
			bx.x1, bx.y1, bx.z1 = math.Min(bx.x1, v.X), math.Min(bx.y1, v.Y), math.Min(bx.z1, v.Z)
			bx.x2, bx.y2, bx.z2 = math.Max(bx.x2, v.X), math.Max(bx.y2, v.Y), math.Max(bx.z2, v.Z)
			allMin = math.Min(allMin, v.Z)
			if p.Kind == citygml.Ground {
				foot, groundSeen = math.Min(foot, v.Z), true
			}
		}
	}
	// v4: a ground polygon high above the lowest one is the underside of something (the pods of
	// the Žižkov tower), not the foot: it gives neither the anchor nor the ground plane.
	isFoot := func(p citygml.Poly) bool {
		if p.Kind != citygml.Ground {
			return false
		}
		if cu.groundFloat <= 0 {
			return true
		}
		lo := math.Inf(1)
		for _, v := range p.Rings[0] {
			lo = math.Min(lo, v.Z)
		}
		return lo <= foot+cu.groundFloat
	}
	if !groundSeen {
		foot = allMin
	}
	keepGroup := make([]bool, len(b.Groups))
	whole := box{math.Inf(1), math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1), math.Inf(-1)}
	for i, bx := range boxes {
		size := math.Max(bx.x2-bx.x1, math.Max(bx.y2-bx.y1, bx.z2-bx.z1))
		keepGroup[i] = size >= detail
		whole = box{math.Min(whole.x1, bx.x1), math.Min(whole.y1, bx.y1), math.Min(whole.z1, bx.z1),
			math.Max(whole.x2, bx.x2), math.Max(whole.y2, bx.y2), math.Max(whole.z2, bx.z2)}
	}
	if math.Max(whole.x2-whole.x1, math.Max(whole.y2-whole.y1, whole.z2-whole.z1)) < detail {
		return nil, nil
	}
	// v4 `parts`: each entry picks the smallest group box (not an installation) around its point.
	// IPR derives walls from the roof edges and often files them under the whole building, so a
	// polygon of any group lying inside the picked box (+ cu.boxSlack) takes the override too.
	type partPick struct {
		pr *config.PartRole
		bx box
	}
	partRole := make([]*config.PartRole, len(b.Groups))
	var picks []partPick
	for k := range mc.Parts {
		pr := &mc.Parts[k]
		best, bestA := -1, math.Inf(1)
		for i, bx := range boxes {
			if b.Groups[i].Installation || pr.XY[0] < bx.x1 || pr.XY[0] > bx.x2 || pr.XY[1] < bx.y1 || pr.XY[1] > bx.y2 {
				continue
			}
			if a := (bx.x2 - bx.x1) * (bx.y2 - bx.y1); a < bestA {
				best, bestA = i, a
			}
		}
		if best < 0 {
			slog.Warn("models: parts entry hits no part", "building", b.ID, "at", pr.At)
			continue
		}
		partRole[best] = pr
		picks = append(picks, partPick{pr, boxes[best]})
	}
	inBox := func(p citygml.Poly, bx box) bool {
		for _, v := range p.Rings[0] {
			if v.X < bx.x1-cu.boxSlack || v.X > bx.x2+cu.boxSlack || v.Y < bx.y1-cu.boxSlack || v.Y > bx.y2+cu.boxSlack {
				return false
			}
		}
		return true
	}
	// Footprint (ground polygons, or every vertex) for the anchor and the base.
	var fp []geo.Pt
	for pass := 0; pass < 2 && len(fp) == 0; pass++ {
		for _, p := range b.Polys {
			if pass == 0 && !isFoot(p) {
				continue
			}
			for _, v := range p.Rings[0] {
				fp = append(fp, geo.Pt{X: v.X, Y: v.Y})
			}
		}
	}
	anchor := centroid(fp)
	ax, ay := geo.DM(anchor.X), geo.DM(anchor.Y)
	part := &pb.ModelPart{AnchorX: ax, AnchorY: ay, SourceId: b.ID}
	// The ground under the part is exaggerated like the terrain (specs/models.md "Pata"): every
	// vertex rises by (exaggeration − 1) × the source ground plane above the foot; heights above
	// the ground stay real. Without ground polygons the part stays rigid.
	var gv []citygml.V3
	for _, p := range b.Polys {
		if isFoot(p) {
			gv = append(gv, p.Rings[0]...)
		}
	}
	plane, planeOK := groundPlane(gv)
	zrel := func(v citygml.V3) float64 {
		z := v.Z - foot
		if planeOK && exag > 1 {
			z += (exag - 1) * (plane[0] + plane[1]*v.X + plane[2]*v.Y - foot)
		}
		return math.Max(0, z)
	}
	if tg != nil {
		if planeOK {
			// The foot sits on the terrain in the median; foot vertices then follow the terrain
			// down (below) so no wall hovers, uphill they stay buried.
			ds := make([]float64, len(gv))
			for i, g := range gv {
				ds[i] = tg.At(geo.Pt{X: g.X, Y: g.Y}) - zrel(g)
			}
			slices.Sort(ds)
			part.BaseZDm = geo.DM(ds[len(ds)/2])
		} else {
			part.BaseZDm = baseZ(tg, fp)
		}
	}
	// Weld on a grid of weld_m (positions are decimetres anyway).
	q := func(x float64) int64 { return int64(math.Round(x / weld)) }
	verts := map[[3]int64]uint32{}
	vert := func(v citygml.V3) (uint32, v3) {
		k := [3]int64{q(v.X), q(v.Y), q(zrel(v))}
		w := v3{float64(k[0]) * weld, float64(k[1]) * weld, float64(k[2]) * weld}
		if i, ok := verts[k]; ok {
			return i, w
		}
		i := uint32(len(part.Positions) / 3)
		verts[k] = i
		part.Positions = append(part.Positions, geo.DM(w.x)-ax, geo.DM(w.y)-ay, geo.DM(w.z))
		return i, w
	}
	var plan []planSrc
	for _, p := range b.Polys {
		if p.Kind == citygml.Ground || !keepGroup[p.Group] {
			continue
		}
		top, real := math.Inf(-1), math.Inf(-1)
		for _, v := range p.Rings[0] {
			top, real = math.Max(top, zrel(v)), math.Max(real, v.Z-foot)
		}
		if real <= 0.05 {
			continue // floor level or below: never seen
		}
		g, gb := b.Groups[p.Group], boxes[p.Group]
		slender := cu.slenderPart(gb.z2-foot, gb.z2-gb.z1, math.Max(gb.x2-gb.x1, gb.y2-gb.y1), g.Installation)
		role := surfaceRole(p.Kind, mc, b.ID, g.ID, g.Usage == towerUsage, slender)
		pr := partRole[p.Group]
		for _, pk := range picks {
			if pr == nil && !g.Installation && inBox(p, pk.bx) {
				pr = pk.pr
			}
		}
		if pr != nil {
			over := pr.Walls
			if p.Kind == citygml.Roof {
				over = pr.Roof
			}
			if r, ok := roleNames[over]; ok {
				role = r
			}
		}
		surface := pb.ModelSurface_SURFACE_WALL
		if p.Kind == citygml.Roof {
			surface = pb.ModelSurface_SURFACE_ROOF
		}
		// Welded, cleaned rings.
		var rings [][]uint32
		var ringsV [][]v3
		for _, r := range p.Rings {
			var ids []uint32
			var vs []v3
			for _, v := range r {
				i, w := vert(v)
				if len(ids) > 0 && ids[len(ids)-1] == i {
					continue
				}
				ids, vs = append(ids, i), append(vs, w)
			}
			if len(ids) > 1 && ids[0] == ids[len(ids)-1] {
				ids, vs = ids[:len(ids)-1], vs[:len(vs)-1]
			}
			ids, vs = dropCollinear(ids, vs, weld/2)
			if len(ids) >= 3 {
				rings, ringsV = append(rings, ids), append(ringsV, vs)
			} else if len(rings) == 0 {
				break // the exterior collapsed
			}
		}
		if len(rings) == 0 {
			continue
		}
		n := newell(ringsV[0])
		if n.norm() < weld*weld {
			continue
		}
		tris := triangulate3(ringsV, n)
		flat := make([]uint32, 0)
		for _, r := range rings {
			flat = append(flat, r...)
		}
		for k := 0; k+2 < len(tris); k += 3 {
			a, bb, c := flat[tris[k]], flat[tris[k+1]], flat[tris[k+2]]
			if a == bb || bb == c || a == c {
				continue
			}
			part.Triangles = append(part.Triangles, a, bb, c)
			part.Roles = append(part.Roles, byte(role))
			part.Surfaces = append(part.Surfaces, byte(surface))
		}
		if p.Kind == citygml.Roof && n.z/n.norm() > 0.02 {
			ps := planSrc{shade: roofShade(n), top: top}
			for _, r := range ringsV {
				pr := make([]geo.Pt, len(r))
				for i, v := range r {
					pr[i] = geo.Pt{X: v.x, Y: v.y}
				}
				ps.rings = append(ps.rings, pr)
			}
			plan = append(plan, ps)
		}
	}
	if len(part.Triangles) == 0 {
		return nil, nil
	}
	seen := map[uint32]bool{}
	for _, g := range gv {
		if i, ok := verts[[3]int64{q(g.X), q(g.Y), q(zrel(g))}]; ok && !seen[i] {
			seen[i] = true
			part.Foot = append(part.Foot, i)
		}
	}
	slices.Sort(part.Foot)
	if tg != nil && planeOK {
		for _, i := range part.Foot {
			p := geo.Pt{X: float64(ax+part.Positions[3*i]) / 10, Y: float64(ay+part.Positions[3*i+1]) / 10}
			part.Positions[3*i+2] = min(part.Positions[3*i+2], geo.DM(tg.At(p))-part.BaseZDm)
		}
	}
	return part, plan
}

// groundPlane fits z = a + b·x + c·y to the ground vertices (least squares).
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

// dropCollinear removes ring vertices within tol of the line through their neighbours.
func dropCollinear(ids []uint32, vs []v3, tol float64) ([]uint32, []v3) {
	for changed := true; changed && len(ids) > 3; {
		changed = false
		for i := 0; i < len(ids) && len(ids) > 3; i++ {
			a, b, c := vs[(i+len(vs)-1)%len(vs)], vs[i], vs[(i+1)%len(vs)]
			ac := c.sub(a)
			l := ac.norm()
			var d float64
			if l < 1e-9 {
				d = b.sub(a).norm()
			} else {
				d = b.sub(a).cross(ac).norm() / l
			}
			if d < tol {
				ids = append(ids[:i], ids[i+1:]...)
				vs = append(vs[:i], vs[i+1:]...)
				changed = true
				i--
			}
		}
	}
	return ids, vs
}

func newell(r []v3) v3 {
	var n v3
	for i := range r {
		a, b := r[i], r[(i+1)%len(r)]
		n.x += (a.y - b.y) * (a.z + b.z)
		n.y += (a.z - b.z) * (a.x + b.x)
		n.z += (a.x - b.x) * (a.y + b.y)
	}
	return n
}

// triangulate3 earcuts a planar 3D polygon in its dominant plane; triangles face along n.
func triangulate3(rings [][]v3, n v3) []int {
	ax, ay, az := math.Abs(n.x), math.Abs(n.y), math.Abs(n.z)
	proj := func(v v3) geo.Pt {
		switch {
		case az >= ax && az >= ay:
			return geo.Pt{X: v.x, Y: v.y}
		case ax >= ay:
			return geo.Pt{X: v.y, Y: v.z}
		}
		return geo.Pt{X: v.z, Y: v.x}
	}
	var r2 [][]geo.Pt
	var flat []v3
	for _, r := range rings {
		pr := make([]geo.Pt, len(r))
		for i, v := range r {
			pr[i] = proj(v)
		}
		r2 = append(r2, pr)
		flat = append(flat, r...)
	}
	idx, err := geo.Triangulate(r2)
	if err != nil {
		return nil
	}
	for k := 0; k+2 < len(idx); k += 3 {
		a, b, c := flat[idx[k]], flat[idx[k+1]], flat[idx[k+2]]
		if b.sub(a).cross(c.sub(a)).dot(n) < 0 {
			idx[k+1], idx[k+2] = idx[k+2], idx[k+1]
		}
	}
	return idx
}

// roofPlan merges one part's roof polygons per shade (shared edges cancel), simplifies and
// triangulates them (specs/models.md, plan ch. 6 step 6).
//
// coarse 0 keeps the four shades apart, 1 merges them in pairs (0+1, 2+3), 2 merges all; a
// merged polygon takes the shade covering most of its area.
func roofPlan(src []planSrc, baseZ int32, simplify float64, coarse int) []*pb.PlanPoly {
	type key = [2]int32
	var out []*pb.PlanPoly
	bucket := func(s uint32) uint32 {
		switch coarse {
		case 0:
			return s
		case 1:
			return s / 2
		}
		return 0
	}
	for shade := uint32(0); shade < 4; shade++ {
		var tops []planSrc
		var keys []key
		var rings [][]key
		var ringPoly []int
		for _, s := range src {
			if bucket(s.shade) != shade {
				continue
			}
			tops = append(tops, s)
			for ri, r := range s.rings {
				rr := geo.Orient(r, ri == 0)
				kr := make([]key, len(rr))
				for i, p := range rr {
					kr[i] = key{geo.DM(p.X), geo.DM(p.Y)}
				}
				keys = append(keys, kr...)
				rings = append(rings, kr)
				ringPoly = append(ringPoly, len(tops)-1)
			}
		}
		if len(tops) == 0 {
			continue
		}
		// Split edges at vertices lying on them (T-junctions), so shared borders cancel.
		polyEdges := make([][][2]key, len(tops))
		for ri, kr := range rings {
			pe := &polyEdges[ringPoly[ri]]
			for i := range kr {
				a, b := kr[i], kr[(i+1)%len(kr)]
				var mids []key
				var ts []float64
				dx, dy := float64(b[0]-a[0]), float64(b[1]-a[1])
				l2 := dx*dx + dy*dy
				if l2 == 0 {
					continue
				}
				for _, k := range keys {
					if k == a || k == b {
						continue
					}
					ex, ey := float64(k[0]-a[0]), float64(k[1]-a[1])
					t := (ex*dx + ey*dy) / l2
					if t <= 0 || t >= 1 {
						continue
					}
					if d := math.Abs(ex*dy-ey*dx) / math.Sqrt(l2); d <= 0.5 { // dm
						mids, ts = append(mids, k), append(ts, t)
					}
				}
				ord := make([]int, len(mids))
				for j := range ord {
					ord[j] = j
				}
				sort.Slice(ord, func(x, y int) bool { return ts[ord[x]] < ts[ord[y]] })
				prev := a
				for _, j := range ord {
					if mids[j] != prev {
						*pe = append(*pe, [2]key{prev, mids[j]})
						prev = mids[j]
					}
				}
				if prev != b {
					*pe = append(*pe, [2]key{prev, b})
				}
			}
		}
		// Only polygons sharing an edge merge (overlapping roofs at other heights stay apart).
		parent := make([]int, len(tops))
		for i := range parent {
			parent[i] = i
		}
		find := func(x int) int {
			for parent[x] != x {
				parent[x] = parent[parent[x]]
				x = parent[x]
			}
			return x
		}
		seenEdge := map[[2]key]int{}
		for pi, pe := range polyEdges {
			for _, e := range pe {
				u := e
				if u[1][0] < u[0][0] || (u[1][0] == u[0][0] && u[1][1] < u[0][1]) {
					u = [2]key{u[1], u[0]}
				}
				if o, ok := seenEdge[u]; ok {
					if ra, rb := find(o), find(pi); ra != rb {
						parent[max(ra, rb)] = min(ra, rb)
					}
				} else {
					seenEdge[u] = pi
				}
			}
		}
		var comps [][]int
		compOf := map[int]int{}
		for pi := range tops {
			r := find(pi)
			ci, ok := compOf[r]
			if !ok {
				ci = len(comps)
				compOf[r] = ci
				comps = append(comps, nil)
			}
			comps[ci] = append(comps[ci], pi)
		}
		allTops := tops
		for _, comp := range comps {
			edges := map[[2]key]int{}
			var tops []planSrc
			for _, pi := range comp {
				tops = append(tops, allTops[pi])
				for _, e := range polyEdges[pi] {
					a, b := e[0], e[1]
					if edges[[2]key{b, a}] > 0 {
						edges[[2]key{b, a}]--
						continue
					}
					edges[[2]key{a, b}]++
				}
			}
			next := map[key][]key{}
			var starts []key
			for e, c := range edges {
				for ; c > 0; c-- {
					next[e[0]] = append(next[e[0]], e[1])
					starts = append(starts, e[0])
				}
			}
			sort.Slice(starts, func(i, j int) bool {
				if starts[i][0] != starts[j][0] {
					return starts[i][0] < starts[j][0]
				}
				return starts[i][1] < starts[j][1]
			})
			for k := range next {
				nk := next[k]
				sort.Slice(nk, func(i, j int) bool {
					if nk[i][0] != nk[j][0] {
						return nk[i][0] < nk[j][0]
					}
					return nk[i][1] < nk[j][1]
				})
			}
			var outers, holes [][]geo.Pt
			for _, s := range starts {
				if len(next[s]) == 0 {
					continue
				}
				var ring []geo.Pt
				cur := s
				for len(next[cur]) > 0 && len(ring) < 100000 {
					ring = append(ring, geo.Pt{X: float64(cur[0]) / 10, Y: float64(cur[1]) / 10})
					nx := next[cur][0]
					next[cur] = next[cur][1:]
					cur = nx
					if cur == s {
						break
					}
				}
				ring = simplifyRing(ring, simplify)
				if len(ring) < 3 {
					continue
				}
				a := geo.SignedArea(ring)
				switch {
				case a > 0.5:
					outers = append(outers, ring)
				case a < -0.5:
					holes = append(holes, ring)
				}
			}
			owner := make([][][]geo.Pt, len(outers))
			for _, h := range holes {
				best, bestA := -1, math.Inf(1)
				for i, o := range outers {
					if a := geo.SignedArea(o); a < bestA && geo.PointInRing(h[0], o) {
						best, bestA = i, a
					}
				}
				if best >= 0 {
					owner[best] = append(owner[best], h)
				}
			}
			for i, o := range outers {
				rings := append([][]geo.Pt{o}, owner[i]...)
				idx, err := geo.Triangulate(rings)
				if err != nil || len(idx) == 0 {
					continue
				}
				pp := &pb.PlanPoly{Shade: shade, BaseZDm: baseZ}
				if coarse > 0 {
					var area [4]float64
					for _, t := range tops {
						if geo.PointInRing(centroid(t.rings[0]), o) {
							area[t.shade] += math.Abs(geo.SignedArea(t.rings[0]))
						}
					}
					for k := range area {
						if area[k] > area[pp.Shade] {
							pp.Shade = uint32(k)
						}
					}
				}
				n := 0
				for _, r := range rings {
					for _, p := range r {
						pp.Points = append(pp.Points, geo.DM(p.X), geo.DM(p.Y))
					}
					n += len(r)
					pp.RingEnds = append(pp.RingEnds, uint32(n))
				}
				for _, k := range idx {
					pp.Triangles = append(pp.Triangles, uint32(k))
				}
				top := 0.0
				for _, t := range tops {
					if geo.PointInRing(centroid(t.rings[0]), o) {
						top = math.Max(top, t.top)
					}
				}
				pp.HeightM = float32(math.Round(top*10) / 10)
				out = append(out, pp)
			}
		}
	}
	return out
}

// simplifyRing is Douglas–Peucker on a closed ring (split at the vertex farthest from the first).
func simplifyRing(r []geo.Pt, tol float64) []geo.Pt {
	if len(r) < 4 {
		return r
	}
	far, fd := 0, -1.0
	for i, p := range r {
		if d := p.Dist(r[0]); d > fd {
			far, fd = i, d
		}
	}
	a := dp(r[:far+1], tol)
	b := dp(append(append([]geo.Pt{}, r[far:]...), r[0]), tol)
	out := append(a[:len(a)-1], b[:len(b)-1]...)
	return out
}

func dp(pts []geo.Pt, tol float64) []geo.Pt {
	if len(pts) < 3 {
		return pts
	}
	idx, d := 0, -1.0
	for i := 1; i < len(pts)-1; i++ {
		q, _ := geo.ClosestOnSegment(pts[i], pts[0], pts[len(pts)-1])
		if dd := q.Dist(pts[i]); dd > d {
			idx, d = i, dd
		}
	}
	if d <= tol {
		return []geo.Pt{pts[0], pts[len(pts)-1]}
	}
	l := dp(pts[:idx+1], tol)
	r := dp(pts[idx:], tol)
	return append(l[:len(l)-1], r...)
}

// modelReplaces lists the pack buildings the model covers at least `share` of (its triangles
// projected from above, sampled on a grid of ≤ 1 m), and every building of the landmark itself
// (`landmark` 1-based, 0 = none).
func modelReplaces(m *pb.Model, chunks map[[2]int]*pb.Chunk, share float64, landmark uint32) []*pb.BuildingRef {
	const cell = 8.0
	type tri struct{ a, b, c geo.Pt }
	grid := map[[2]int][]tri{}
	mx1, my1, mx2, my2 := math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)
	for _, part := range m.Parts {
		pt := func(i uint32) geo.Pt {
			return geo.Pt{X: float64(part.AnchorX+part.Positions[3*i]) / 10, Y: float64(part.AnchorY+part.Positions[3*i+1]) / 10}
		}
		for k := 0; k+2 < len(part.Triangles); k += 3 {
			t := tri{pt(part.Triangles[k]), pt(part.Triangles[k+1]), pt(part.Triangles[k+2])}
			if math.Abs(t.b.Sub(t.a).Cross(t.c.Sub(t.a))) < 0.02 {
				continue // a wall seen from above
			}
			x1, y1 := math.Min(t.a.X, math.Min(t.b.X, t.c.X)), math.Min(t.a.Y, math.Min(t.b.Y, t.c.Y))
			x2, y2 := math.Max(t.a.X, math.Max(t.b.X, t.c.X)), math.Max(t.a.Y, math.Max(t.b.Y, t.c.Y))
			mx1, my1, mx2, my2 = math.Min(mx1, x1), math.Min(my1, y1), math.Max(mx2, x2), math.Max(my2, y2)
			for gx := int(math.Floor(x1 / cell)); gx <= int(math.Floor(x2/cell)); gx++ {
				for gy := int(math.Floor(y1 / cell)); gy <= int(math.Floor(y2/cell)); gy++ {
					grid[[2]int{gx, gy}] = append(grid[[2]int{gx, gy}], t)
				}
			}
		}
	}
	covered := func(q geo.Pt) bool {
		for _, t := range grid[[2]int{int(math.Floor(q.X / cell)), int(math.Floor(q.Y / cell))}] {
			d1, d2, d3 := t.b.Sub(t.a).Cross(q.Sub(t.a)), t.c.Sub(t.b).Cross(q.Sub(t.b)), t.a.Sub(t.c).Cross(q.Sub(t.c))
			if (d1 >= 0 && d2 >= 0 && d3 >= 0) || (d1 <= 0 && d2 <= 0 && d3 <= 0) {
				return true
			}
		}
		return false
	}
	keys := make([][2]int, 0, len(chunks))
	for k := range chunks {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i][1] != keys[j][1] {
			return keys[i][1] < keys[j][1]
		}
		return keys[i][0] < keys[j][0]
	})
	var out []*pb.BuildingRef
	for _, k := range keys {
		for bi, b := range chunks[k].Buildings {
			end := len(b.Rings) / 2
			if len(b.RingEnds) > 0 {
				end = int(b.RingEnds[0])
			}
			ring := make([]geo.Pt, end)
			x1, y1, x2, y2 := math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)
			for i := range ring {
				ring[i] = geo.Pt{X: float64(b.Rings[2*i]) / 10, Y: float64(b.Rings[2*i+1]) / 10}
				x1, y1, x2, y2 = math.Min(x1, ring[i].X), math.Min(y1, ring[i].Y), math.Max(x2, ring[i].X), math.Max(y2, ring[i].Y)
			}
			if landmark > 0 && b.Landmark == landmark {
				out = append(out, &pb.BuildingRef{ChunkX: int32(k[0]), ChunkY: int32(k[1]), Index: uint32(bi)})
				continue
			}
			if x2 < mx1 || x1 > mx2 || y2 < my1 || y1 > my2 {
				continue
			}
			in, cov := 0, 0
			step := math.Max(0.5, math.Min(1, math.Min(x2-x1, y2-y1)/4))
			for y := y1 + step/2; y < y2; y += step {
				for x := x1 + step/2; x < x2; x += step {
					q := geo.Pt{X: x, Y: y}
					if !geo.PointInRing(q, ring) {
						continue
					}
					in++
					if covered(q) {
						cov++
					}
				}
			}
			if in > 0 && float64(cov) >= share*float64(in) {
				out = append(out, &pb.BuildingRef{ChunkX: int32(k[0]), ChunkY: int32(k[1]), Index: uint32(bi)})
			}
		}
	}
	return out
}
