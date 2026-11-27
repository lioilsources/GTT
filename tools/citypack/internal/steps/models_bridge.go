package steps

import (
	"fmt"
	"log/slog"
	"math"
	"path/filepath"
	"slices"
	"strconv"
	"strings"

	"citypack/internal/citygml"
	"citypack/internal/config"
	"citypack/internal/duck"
	"citypack/internal/geo"
	"citypack/internal/pb"
)

// bridgePrefix marks a bridge part (specs/models.md v3 "Mosty"): source_id "bridge:<ID_BUD>",
// the same key in models.yaml `roles` / `walls`.
const bridgePrefix = "bridge:"

// isBridgePart says whether a model part is a bridge of the IPR "Mosty 3D" set.
func isBridgePart(p *pb.ModelPart) bool { return strings.HasPrefix(p.SourceId, bridgePrefix) }

// readBridges reads the bridges of one model from the IPR "Mosty 3D" shapefile (polygonZ in
// S-JTSK, one row per face, ID_BUD per bridge) into local metres (specs/models.md v3 "Mosty").
// The rings have no reliable orientation; buildBridgePart orients them.
func (e *Env) readBridges(mc config.ModelConfig, srs string) ([]*srcBuilding, error) {
	if len(mc.Bridges.IDs) == 0 {
		return nil, nil
	}
	if mc.Bridges.File == "" {
		return nil, fmt.Errorf("models.yaml: bridges.ids without bridges.file")
	}
	path := filepath.Join(e.Work, "raw", "models", mc.Bridges.File)
	ids := make([]string, len(mc.Bridges.IDs))
	for i, id := range mc.Bridges.IDs {
		ids[i] = strconv.FormatInt(id, 10)
	}
	rows, err := duck.Query("models bridges", "", fmt.Sprintf(
		"SELECT ID_BUD AS id, ST_AsText(geom) AS w FROM ST_Read(%s) WHERE ID_BUD IN (%s) ORDER BY OGC_FID",
		duck.Quote(path), strings.Join(ids, ", ")))
	if err != nil {
		return nil, err
	}
	type face struct {
		id    string
		rings [][]citygml.V3
	}
	var faces []face
	x1, y1, x2, y2 := math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)
	for _, r := range rows {
		rings, err := parsePolygonZ(r[1])
		if err != nil {
			return nil, fmt.Errorf("%s ID_BUD %s: %w", mc.Bridges.File, r[0], err)
		}
		for _, v := range rings[0] {
			x1, y1, x2, y2 = math.Min(x1, v.X), math.Min(y1, v.Y), math.Max(x2, v.X), math.Max(y2, v.Y)
		}
		faces = append(faces, face{r[0], rings})
	}
	if len(faces) == 0 {
		return nil, fmt.Errorf("%s: none of ID_BUD %v found", mc.Bridges.File, mc.Bridges.IDs)
	}
	af, err := e.fitAffine(srs, x1-1, y1-1, x2+1, y2+1)
	if err != nil {
		return nil, err
	}
	byID := map[string]*srcBuilding{}
	var out []*srcBuilding
	for _, f := range faces {
		b := byID[f.id]
		if b == nil {
			b = &srcBuilding{ID: bridgePrefix + f.id, Bridge: true, Groups: []citygml.Group{{ID: bridgePrefix + f.id, Usage: "bridge"}}}
			byID[f.id] = b
			out = append(out, b)
		}
		p := citygml.Poly{Kind: citygml.Wall}
		for _, r := range f.rings {
			lr := make([]citygml.V3, len(r))
			for i, v := range r {
				q := af.apply(geo.Pt{X: v.X, Y: v.Y})
				lr[i] = citygml.V3{X: q.X, Y: q.Y, Z: v.Z}
			}
			p.Rings = append(p.Rings, lr)
		}
		b.Polys = append(b.Polys, p)
	}
	for _, b := range out {
		var sx, sy float64
		n := 0
		for _, p := range b.Polys {
			for _, v := range p.Rings[0] {
				sx, sy, n = sx+v.X, sy+v.Y, n+1
			}
		}
		b.C = geo.Pt{X: sx / float64(n), Y: sy / float64(n)}
		slog.Info("models: bridge read", "id", b.ID, "faces", len(b.Polys), "affine_residual_m", fmt.Sprintf("%.3f", af.residual))
	}
	return out, nil
}

// parsePolygonZ reads WKT "POLYGON Z ((x y z, …), (…))" into open rings (exterior first).
func parsePolygonZ(w string) ([][]citygml.V3, error) {
	w = strings.TrimSpace(w)
	if !strings.HasPrefix(w, "POLYGON Z") {
		return nil, fmt.Errorf("not a POLYGON Z: %.30s", w)
	}
	body := strings.TrimSpace(strings.TrimPrefix(w, "POLYGON Z"))
	if !strings.HasPrefix(body, "((") || !strings.HasSuffix(body, "))") {
		return nil, fmt.Errorf("malformed polygon: %.30s", w)
	}
	var rings [][]citygml.V3
	for _, rs := range strings.Split(body[2:len(body)-2], "), (") {
		var r []citygml.V3
		for _, ps := range strings.Split(rs, ",") {
			f := strings.Fields(ps)
			if len(f) != 3 {
				return nil, fmt.Errorf("vertex %q: want x y z", ps)
			}
			var c [3]float64
			for i := range c {
				v, err := strconv.ParseFloat(f[i], 64)
				if err != nil {
					return nil, err
				}
				c[i] = v
			}
			r = append(r, citygml.V3{X: c[0], Y: c[1], Z: c[2]})
		}
		if len(r) > 1 && r[0] == r[len(r)-1] {
			r = r[:len(r)-1]
		}
		if len(r) >= 3 {
			rings = append(rings, r)
		} else if len(rings) == 0 {
			return nil, fmt.Errorf("degenerate exterior ring")
		}
	}
	return rings, nil
}

// bridgeFlat is |n_z| above which a bridge face counts as horizontal (deck, cornice, pier top).
const bridgeFlat = 0.9

// buildBridgePart turns one bridge into a model part (specs/models.md v3 "Mosty"). Heights stay
// real (no display scaling: every z ≤ 0) and the deck sits on the terrain at both ends: per end
// the median of terrain − z over the deck vertices within models.bridge_end_m of it along the
// bridge's main axis (deck = horizontal faces at most 2 m below the highest one of that end);
// between the ends the offset runs linearly (a shear: the exaggerated banks differ, the real
// bridge is level). base_z is the higher end, z = 0 the top of the bridge there. Horizontal faces
// face up; other faces are drawn from both sides because the source rings are not oriented.
// Every face is SURFACE_ROOF (no window texture).
func buildBridgePart(b *srcBuilding, mc config.ModelConfig, detail, weld, endM float64, tg *TerrainGrid) (*pb.ModelPart, []planSrc) {
	type face struct {
		rings [][]v3
		n     v3
	}
	var faces []face
	flats := 0
	zref := math.Inf(-1)
	var all []geo.Pt
	for _, p := range b.Polys {
		lo, hi := v3{math.Inf(1), math.Inf(1), math.Inf(1)}, v3{math.Inf(-1), math.Inf(-1), math.Inf(-1)}
		var rings [][]v3
		for _, r := range p.Rings {
			rr := make([]v3, len(r))
			for i, v := range r {
				rr[i] = v3{v.X, v.Y, v.Z}
				lo = v3{math.Min(lo.x, v.X), math.Min(lo.y, v.Y), math.Min(lo.z, v.Z)}
				hi = v3{math.Max(hi.x, v.X), math.Max(hi.y, v.Y), math.Max(hi.z, v.Z)}
			}
			rings = append(rings, rr)
		}
		if math.Max(hi.x-lo.x, math.Max(hi.y-lo.y, hi.z-lo.z)) < detail {
			continue // below the detail like small groups of buildings
		}
		n := newell(rings[0])
		if n.norm() < weld*weld {
			continue
		}
		if math.Abs(n.z)/n.norm() > bridgeFlat {
			if n.z < 0 {
				n = v3{-n.x, -n.y, -n.z}
			}
			flats++
		}
		for _, v := range rings[0] {
			all = append(all, geo.Pt{X: v.x, Y: v.y})
			zref = math.Max(zref, v.z)
		}
		faces = append(faces, face{rings, n})
	}
	if len(faces) == 0 || flats == 0 {
		return nil, nil
	}
	anchor := centroid(all)
	ax, ay := geo.DM(anchor.X), geo.DM(anchor.Y)
	part := &pb.ModelPart{AnchorX: ax, AnchorY: ay, SourceId: b.ID}
	// Main axis of the bridge (principal component of the face vertices).
	var sxx, sxy, syy float64
	for _, p := range all {
		dx, dy := p.X-anchor.X, p.Y-anchor.Y
		sxx, sxy, syy = sxx+dx*dx, sxy+dx*dy, syy+dy*dy
	}
	th := 0.5 * math.Atan2(2*sxy, sxx-syy)
	axis := geo.Pt{X: math.Cos(th), Y: math.Sin(th)}
	along := func(x, y float64) float64 { return (x-anchor.X)*axis.X + (y-anchor.Y)*axis.Y }
	t0, t1 := math.Inf(1), math.Inf(-1)
	for _, p := range all {
		t := along(p.X, p.Y)
		t0, t1 = math.Min(t0, t), math.Max(t1, t)
	}
	var off [2]float64
	if tg != nil {
		var ends [2][]float64
		for end := 0; end < 2; end++ {
			at := func(v v3) bool {
				t := along(v.x, v.y)
				return (end == 0 && t-t0 <= endM) || (end == 1 && t1-t <= endM)
			}
			var vs []v3
			top := math.Inf(-1)
			for _, f := range faces {
				if math.Abs(f.n.z)/f.n.norm() <= bridgeFlat {
					continue
				}
				for _, v := range f.rings[0] {
					if at(v) {
						vs, top = append(vs, v), math.Max(top, v.z)
					}
				}
			}
			for _, v := range vs {
				if v.z >= top-2 { // the deck, not pier tops or cornices below it
					ends[end] = append(ends[end], tg.At(geo.Pt{X: v.x, Y: v.y})-(v.z-zref))
				}
			}
		}
		for end, ds := range ends {
			if len(ds) == 0 {
				ds = ends[1-end]
			}
			if len(ds) == 0 {
				off[end] = float64(baseZ(tg, all)) / 10
				continue
			}
			slices.Sort(ds)
			off[end] = ds[len(ds)/2]
		}
	}
	baseOff := math.Max(off[0], off[1])
	part.BaseZDm = geo.DM(baseOff)
	shear := func(v v3) float64 {
		f := 0.0
		if t1 > t0 {
			f = (along(v.x, v.y) - t0) / (t1 - t0)
		}
		return off[0] + (off[1]-off[0])*f - baseOff
	}
	q := func(x float64) int64 { return int64(math.Round(x / weld)) }
	verts := map[[3]int64]uint32{}
	vert := func(v v3) (uint32, v3) {
		k := [3]int64{q(v.x), q(v.y), q(v.z - zref + shear(v))}
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
	for _, f := range faces {
		flat := math.Abs(f.n.z)/f.n.norm() > bridgeFlat
		kind := citygml.Wall
		if flat {
			kind = citygml.Roof
		}
		role := surfaceRole(kind, mc, b.ID, "", false, false)
		var rings [][]uint32
		var ringsV [][]v3
		for _, r := range f.rings {
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
				break
			}
		}
		if len(rings) == 0 {
			continue
		}
		n := newell(ringsV[0])
		if n.norm() < weld*weld {
			continue
		}
		if n.dot(f.n) < 0 {
			n = v3{-n.x, -n.y, -n.z}
		}
		tris := triangulate3(ringsV, n)
		var flatIDs []uint32
		for _, r := range rings {
			flatIDs = append(flatIDs, r...)
		}
		add := func(a, bb, c uint32) {
			part.Triangles = append(part.Triangles, a, bb, c)
			part.Roles = append(part.Roles, byte(role))
			part.Surfaces = append(part.Surfaces, byte(pb.ModelSurface_SURFACE_ROOF))
		}
		for k := 0; k+2 < len(tris); k += 3 {
			a, bb, c := flatIDs[tris[k]], flatIDs[tris[k+1]], flatIDs[tris[k+2]]
			if a == bb || bb == c || a == c {
				continue
			}
			add(a, bb, c)
			if !flat {
				add(a, c, bb)
			}
		}
		if flat {
			top := math.Inf(-1)
			for _, v := range ringsV[0] {
				top = math.Max(top, v.z)
			}
			ps := planSrc{shade: roofShade(n), top: math.Max(weld, top)}
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
	slog.Info("models: bridge part", "id", b.ID, "top_real_m", fmt.Sprintf("%.1f", zref),
		"top_game_m_ends", fmt.Sprintf("%.1f / %.1f", off[0], off[1]), "length_m", fmt.Sprintf("%.0f", t1-t0), "tris", len(part.Roles))
	return part, plan
}

// bridgeRoadHit is the worst clash of a bridge face with a road (validate, specs/models.md v3).
type bridgeRoadHit struct {
	n    int
	dz   float64 // face height − road height at the worst sample
	at   geo.Pt
	road string
}

// bridgeRoadClash samples every road of the graph (centre line and both edges, every metre)
// under a bridge part and counts samples where a face of the part lies from below m below the
// road surface up to clear m above it: the bridge would cover the road or fight it in depth.
// With hit != nil, hit[t] is set for every such triangle t.
func bridgeRoadClash(part *pb.ModelPart, g *pb.Graph, clear, below float64, hits []bool) bridgeRoadHit {
	type tri struct {
		a, b, c                geo.Pt
		za, zb, zc             float64
		minX, minY, maxX, maxY float64
		k                      int
	}
	ax, ay := float64(part.AnchorX)/10, float64(part.AnchorY)/10
	base := float64(part.BaseZDm) / 10
	pos := func(i uint32) (geo.Pt, float64) {
		return geo.Pt{X: ax + float64(part.Positions[3*i])/10, Y: ay + float64(part.Positions[3*i+1])/10},
			base + float64(part.Positions[3*i+2])/10
	}
	const cell = 4.0
	grid := map[[2]int][]int{}
	var tris []tri
	bx1, by1, bx2, by2 := math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)
	nv := uint32(len(part.Positions) / 3)
	for k := 0; k+2 < len(part.Triangles); k += 3 {
		if max(part.Triangles[k], part.Triangles[k+1], part.Triangles[k+2]) >= nv {
			continue // reported by validate
		}
		a, za := pos(part.Triangles[k])
		b, zb := pos(part.Triangles[k+1])
		c, zc := pos(part.Triangles[k+2])
		t := tri{a, b, c, za, zb, zc, math.Min(a.X, math.Min(b.X, c.X)), math.Min(a.Y, math.Min(b.Y, c.Y)),
			math.Max(a.X, math.Max(b.X, c.X)), math.Max(a.Y, math.Max(b.Y, c.Y)), k / 3}
		if (b.X-a.X)*(c.Y-a.Y)-(b.Y-a.Y)*(c.X-a.X) == 0 {
			continue // vertical face: seen from above it covers nothing
		}
		tris = append(tris, t)
		for i := int(math.Floor(t.minX / cell)); i <= int(math.Floor(t.maxX/cell)); i++ {
			for j := int(math.Floor(t.minY / cell)); j <= int(math.Floor(t.maxY/cell)); j++ {
				grid[[2]int{i, j}] = append(grid[[2]int{i, j}], len(tris)-1)
			}
		}
		bx1, by1, bx2, by2 = math.Min(bx1, t.minX), math.Min(by1, t.minY), math.Max(bx2, t.maxX), math.Max(by2, t.maxY)
	}
	hit := bridgeRoadHit{dz: math.Inf(1)}
	for _, ed := range g.Edges {
		if ed.Tunnel {
			continue
		}
		pts, zs := EdgePts(ed), edgeZ(ed)
		if len(zs) != len(pts) {
			zs = make([]float64, len(pts)) // flat pack
		}
		hw := float64(ed.WidthM) / 2
		for k := 1; k < len(pts); k++ {
			p0, p1 := pts[k-1], pts[k]
			l := p0.Dist(p1)
			if l < 1e-6 || math.Max(p0.X, p1.X)+hw < bx1 || math.Min(p0.X, p1.X)-hw > bx2 ||
				math.Max(p0.Y, p1.Y)+hw < by1 || math.Min(p0.Y, p1.Y)-hw > by2 {
				continue
			}
			nx, ny := -(p1.Y-p0.Y)/l, (p1.X-p0.X)/l
			for s := 0.0; s <= l; s += 1 {
				f := s / l
				c := geo.Pt{X: p0.X + (p1.X-p0.X)*f, Y: p0.Y + (p1.Y-p0.Y)*f}
				zr := zs[k-1] + (zs[k]-zs[k-1])*f
				for _, o := range []float64{-hw, 0, hw} {
					q := geo.Pt{X: c.X + nx*o, Y: c.Y + ny*o}
					for _, ti := range grid[[2]int{int(math.Floor(q.X / cell)), int(math.Floor(q.Y / cell))}] {
						t := tris[ti]
						if q.X < t.minX || q.X > t.maxX || q.Y < t.minY || q.Y > t.maxY {
							continue
						}
						w0, w1, w2, ok := baryXY(q, t.a, t.b, t.c)
						if !ok {
							continue
						}
						dz := w0*t.za + w1*t.zb + w2*t.zc - zr
						if dz > -below && dz < clear {
							if hits != nil {
								hits[t.k] = true
							}
							hit.n++
							if math.Abs(dz) < math.Abs(hit.dz) {
								hit.dz, hit.at, hit.road = dz, q, g.Names[ed.Name]
							}
						}
					}
				}
			}
		}
	}
	return hit
}

// baryXY returns the barycentric weights of q in the triangle's plan (inside only).
func baryXY(q, a, b, c geo.Pt) (float64, float64, float64, bool) {
	d := (b.Y-c.Y)*(a.X-c.X) + (c.X-b.X)*(a.Y-c.Y)
	if d == 0 {
		return 0, 0, 0, false
	}
	w0 := ((b.Y-c.Y)*(q.X-c.X) + (c.X-b.X)*(q.Y-c.Y)) / d
	w1 := ((c.Y-a.Y)*(q.X-c.X) + (a.X-c.X)*(q.Y-c.Y)) / d
	w2 := 1 - w0 - w1
	const eps = -1e-9
	return w0, w1, w2, w0 >= eps && w1 >= eps && w2 >= eps
}

// clipBridgeRoads drops the triangles of a bridge part that would cover a road or fight it in
// depth (bridgeRoadClash; specs/models.md v3 "Mosty"): where a bridge end meets a street, the
// street wins, and an arch over a narrow lane loses its springing inside the road corridor.
// Returns the number of triangles dropped.
func clipBridgeRoads(part *pb.ModelPart, g *pb.Graph, clear, below float64) int {
	nt := len(part.Triangles) / 3
	hits := make([]bool, nt)
	bridgeRoadClash(part, g, clear, below, hits)
	var tris []uint32
	var roles, surfs []byte
	for t := 0; t < nt; t++ {
		if hits[t] {
			continue
		}
		tris = append(tris, part.Triangles[3*t:3*t+3]...)
		roles = append(roles, part.Roles[t])
		if t < len(part.Surfaces) {
			surfs = append(surfs, part.Surfaces[t])
		}
	}
	part.Triangles, part.Roles, part.Surfaces = tris, roles, surfs
	return nt - len(roles)
}
