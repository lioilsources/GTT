package steps

import (
	"math"
	"testing"

	"citypack/internal/citygml"
	"citypack/internal/config"
	"citypack/internal/geo"
	"citypack/internal/pb"
)

// box is a source building: ground at z0 (+ slope·x), walls and a flat roof at z0 + h.
func box(id string, x0, y0, w, h, z0 float64, tower bool) *srcBuilding {
	c := []citygml.V3{{X: x0, Y: y0}, {X: x0 + w, Y: y0}, {X: x0 + w, Y: y0 + w}, {X: x0, Y: y0 + w}}
	b := &srcBuilding{ID: id, Groups: []citygml.Group{{ID: id}}, C: geo.Pt{X: x0 + w/2, Y: y0 + w/2}}
	usage := ""
	if tower {
		usage = towerUsage
	}
	b.Groups[0].Usage = usage
	var ground, roof []citygml.V3
	for i := 3; i >= 0; i-- {
		ground = append(ground, citygml.V3{X: c[i].X, Y: c[i].Y, Z: z0})
	}
	for _, p := range c {
		roof = append(roof, citygml.V3{X: p.X, Y: p.Y, Z: z0 + h})
	}
	b.Polys = append(b.Polys, citygml.Poly{Kind: citygml.Ground, Rings: [][]citygml.V3{ground}})
	b.Polys = append(b.Polys, citygml.Poly{Kind: citygml.Roof, Rings: [][]citygml.V3{roof}})
	for i := range c {
		a, d := c[i], c[(i+1)%4]
		b.Polys = append(b.Polys, citygml.Poly{Kind: citygml.Wall, Rings: [][]citygml.V3{{
			{X: a.X, Y: a.Y, Z: z0}, {X: d.X, Y: d.Y, Z: z0}, {X: d.X, Y: d.Y, Z: z0 + h}, {X: a.X, Y: a.Y, Z: z0 + h},
		}}})
	}
	return b
}

func flatTerrain(z float64) *TerrainGrid {
	t := &TerrainGrid{CX0: -2, CY0: -2, W: 129, H: 129, Step: 8, ChunkM: 256, Z: make([]int16, 129*129)}
	for i := range t.Z {
		t.Z[i] = int16(z * 10)
	}
	return t
}

func TestBuildPartBox(t *testing.T) {
	part, plan := buildPart(box("_b", 0, 0, 10, 20, 250, false), config.ModelConfig{}, copperRule{}, 1.5, 0.1, flatTerrain(30), 2)
	if part == nil {
		t.Fatal("no part")
	}
	if n := len(part.Roles); n != 10 {
		t.Fatalf("triangles %d, want 10 (4 walls + roof)", n)
	}
	if len(part.Positions)/3 != 8 || len(part.Foot) != 4 {
		t.Fatalf("vertices %d foot %d, want 8 and 4", len(part.Positions)/3, len(part.Foot))
	}
	if part.AnchorX != 50 || part.AnchorY != 50 || part.BaseZDm != 300 {
		t.Fatalf("anchor %d,%d base %d", part.AnchorX, part.AnchorY, part.BaseZDm)
	}
	roofs, walls := 0, 0
	for _, r := range part.Roles {
		switch pb.ModelRole(r) {
		case pb.ModelRole_ROLE_ROOF:
			roofs++
		case pb.ModelRole_ROLE_WALL:
			walls++
		}
	}
	if roofs != 2 || walls != 8 {
		t.Fatalf("roles roof %d wall %d", roofs, walls)
	}
	// Triangles face outwards: the roof normal points up.
	pos := func(i uint32) v3 {
		return v3{float64(part.Positions[3*i]), float64(part.Positions[3*i+1]), float64(part.Positions[3*i+2])}
	}
	for k := 0; k < len(part.Triangles); k += 3 {
		a, b, c := pos(part.Triangles[k]), pos(part.Triangles[k+1]), pos(part.Triangles[k+2])
		n := b.sub(a).cross(c.sub(a))
		mid := v3{(a.x + b.x + c.x) / 3, (a.y + b.y + c.y) / 3, (a.z + b.z + c.z) / 3}
		out := mid.sub(v3{0, 0, 100}) // the box centre in dm from the anchor
		if n.dot(out) <= 0 {
			t.Fatalf("triangle %d faces inwards", k/3)
		}
	}
	if len(plan) != 1 || plan[0].top != 20 {
		t.Fatalf("plan %+v", plan)
	}
	// The detail filter drops the whole part when it is smaller.
	if p, _ := buildPart(box("_s", 0, 0, 1, 1, 0, false), config.ModelConfig{}, copperRule{}, 1.5, 0.1, nil, 2); p != nil {
		t.Fatal("small part kept")
	}
}

func TestBuildPartRoles(t *testing.T) {
	part, _ := buildPart(box("_t", 0, 0, 4, 30, 0, true), config.ModelConfig{}, copperRule{}, 1.5, 0.1, nil, 1)
	if pb.ModelRole(part.Roles[len(part.Roles)-1]) != pb.ModelRole_ROLE_COPPER && pb.ModelRole(part.Roles[0]) != pb.ModelRole_ROLE_COPPER {
		t.Fatal("tower roof is not copper")
	}
	// v2: a part id in `roles` beats the tower rule.
	b := box("_t", 0, 0, 4, 30, 0, true)
	b.Groups[0].ID = "_t_part"
	mc := config.ModelConfig{Roles: map[string]string{"_t_part": "gold"}, Walls: map[string]string{"_t": "stone"}}
	part, _ = buildPart(b, mc, copperRule{}, 1.5, 0.1, nil, 1)
	count := func(r pb.ModelRole) int {
		n := 0
		for _, x := range part.Roles {
			if pb.ModelRole(x) == r {
				n++
			}
		}
		return n
	}
	if count(pb.ModelRole_ROLE_GOLD) != 2 || count(pb.ModelRole_ROLE_STONE) != 8 {
		t.Fatalf("gold roof %d (want 2), stone walls %d (want 8)", count(pb.ModelRole_ROLE_GOLD), count(pb.ModelRole_ROLE_STONE))
	}
	// Surfaces keep the CityGML class, one per triangle.
	if len(part.Surfaces) != len(part.Roles) {
		t.Fatalf("surfaces %d, roles %d", len(part.Surfaces), len(part.Roles))
	}
	roofs := 0
	for _, s := range part.Surfaces {
		if pb.ModelSurface(s) == pb.ModelSurface_SURFACE_ROOF {
			roofs++
		}
	}
	if roofs != 2 {
		t.Fatalf("roof surfaces %d, want 2", roofs)
	}
	// Slender tall part without the IPR mark: copper roof by shape (4 m wide, 30 m high).
	cu := copperRule{minTop: 25, slender: 0.4}
	part, _ = buildPart(box("_u", 0, 0, 4, 30, 0, false), config.ModelConfig{}, cu, 1.5, 0.1, nil, 1)
	if count(pb.ModelRole_ROLE_COPPER) != 2 || count(pb.ModelRole_ROLE_WALL) != 8 {
		t.Fatalf("slender part: copper %d (want 2), wall %d (want 8)", count(pb.ModelRole_ROLE_COPPER), count(pb.ModelRole_ROLE_WALL))
	}
	// A wide block of the same height keeps its roof.
	part, _ = buildPart(box("_w", 0, 0, 20, 30, 0, false), config.ModelConfig{}, cu, 1.5, 0.1, nil, 1)
	if count(pb.ModelRole_ROLE_COPPER) != 0 {
		t.Fatal("wide block got copper")
	}
}

func TestSurfaceRole(t *testing.T) {
	mc := config.ModelConfig{
		Roles: map[string]string{"_c": "slate", "_spire": "gold"},
		Walls: map[string]string{"_c": "stone", "_glass": "glass", "_x": "nonsense"},
	}
	for _, c := range []struct {
		name           string
		kind           citygml.Kind
		bld, part      string
		tower, slender bool
		want           pb.ModelRole
	}{
		{"plain wall", citygml.Wall, "_a", "_a", false, false, pb.ModelRole_ROLE_WALL},
		{"plain roof", citygml.Roof, "_a", "_a", false, false, pb.ModelRole_ROLE_ROOF},
		{"tower roof", citygml.Roof, "_a", "", true, false, pb.ModelRole_ROLE_COPPER},
		{"slender roof", citygml.Roof, "_a", "", false, true, pb.ModelRole_ROLE_COPPER},
		{"tower wall stays wall", citygml.Wall, "_a", "", true, true, pb.ModelRole_ROLE_WALL},
		{"building roof override", citygml.Roof, "_c", "_c", false, false, pb.ModelRole_ROLE_SLATE},
		{"building wall override", citygml.Wall, "_c", "", true, false, pb.ModelRole_ROLE_STONE},
		{"tower beats building roof override", citygml.Roof, "_c", "", true, false, pb.ModelRole_ROLE_COPPER},
		{"part roof override beats tower", citygml.Roof, "_c", "_spire", true, false, pb.ModelRole_ROLE_GOLD},
		{"part wall override", citygml.Wall, "_c", "_glass", false, false, pb.ModelRole_ROLE_GLASS},
		{"unknown role name ignored", citygml.Wall, "_x", "_x", false, false, pb.ModelRole_ROLE_WALL},
	} {
		if got := surfaceRole(c.kind, mc, c.bld, c.part, c.tower, c.slender); got != c.want {
			t.Errorf("%s: %v, want %v", c.name, got, c.want)
		}
	}
	cu := copperRule{minTop: 30, slender: 0.4}
	for _, c := range []struct {
		top, h, fp float64
		inst       bool
		want       bool
	}{
		{90, 89, 18, false, true},   // the cathedral's main tower
		{40, 40, 5, false, true},    // a turret
		{52, 52, 105, false, false}, // the nave
		{29, 29, 5, false, false},   // too low
		{45, 11, 2, true, false},    // a chimney (installation)
	} {
		if got := cu.slenderPart(c.top, c.h, c.fp, c.inst); got != c.want {
			t.Errorf("slender(%v): %v, want %v", c, got, c.want)
		}
	}
	if (copperRule{}).slenderPart(90, 90, 1, false) {
		t.Error("zero rule must be off")
	}
}

func TestBuildPartSlopeShear(t *testing.T) {
	// Ground rising 1 m per 10 m in x: with exaggeration 2 the far wall bottom rises 1 m more.
	b := box("_s", 0, 0, 10, 10, 0, false)
	for pi := range b.Polys {
		for ri := range b.Polys[pi].Rings {
			for vi := range b.Polys[pi].Rings[ri] {
				v := &b.Polys[pi].Rings[ri][vi]
				v.Z += v.X / 10
			}
		}
	}
	part, _ := buildPart(b, config.ModelConfig{}, copperRule{}, 1.5, 0.1, flatTerrain(0), 2)
	// The roof keeps the doubled slope: 10 m high plus 2 m at the far side.
	maxZ := int32(0)
	for i := 2; i < len(part.Positions); i += 3 {
		maxZ = max(maxZ, part.Positions[i])
	}
	if maxZ != 120 {
		t.Fatalf("roof top %d dm, want 120 (10 m + 1 m source slope × 2)", maxZ)
	}
	// The foot sits on the flat terrain in the median and its vertices follow it: nothing hovers.
	if part.BaseZDm != 0 {
		t.Fatalf("base %d, want 0", part.BaseZDm)
	}
	for _, i := range part.Foot {
		if z := part.Positions[3*i+2]; z != 0 {
			t.Fatalf("foot vertex %d at %d dm, want on the terrain (0)", i, z)
		}
	}
}

func TestRoofPlanMerge(t *testing.T) {
	sq := func(x0, y0, w float64) []geo.Pt {
		return []geo.Pt{{X: x0, Y: y0}, {X: x0 + w, Y: y0}, {X: x0 + w, Y: y0 + w}, {X: x0, Y: y0 + w}}
	}
	// Two squares sharing an edge, a third one with a T-junction on it: one polygon.
	src := []planSrc{
		{rings: [][]geo.Pt{sq(0, 0, 10)}, shade: 2, top: 5},
		{rings: [][]geo.Pt{sq(10, 0, 10)}, shade: 2, top: 7},
		{rings: [][]geo.Pt{{{X: 0, Y: 10}, {X: 5, Y: 10}, {X: 5, Y: 15}, {X: 0, Y: 15}}}, shade: 2, top: 9},
		{rings: [][]geo.Pt{sq(40, 0, 10)}, shade: 0, top: 3},
	}
	out := roofPlan(src, 12, 0.3, 0)
	if len(out) != 2 {
		t.Fatalf("polys %d, want 2", len(out))
	}
	var merged *pb.PlanPoly
	for _, p := range out {
		if p.Shade == 2 {
			merged = p
		}
	}
	if merged == nil || merged.HeightM != 9 || merged.BaseZDm != 12 || math.Abs(planArea(merged)-225) > 0.1 {
		t.Fatalf("merged %+v area %.1f", merged, planArea(merged))
	}
	if got := len(roofPlan(src, 0, 0.3, 2)); got != 2 {
		t.Fatalf("coarse plan %d polys, want 2 (disjoint)", got)
	}
}

func TestRoofShade(t *testing.T) {
	if roofShade(v3{0, 0, 1}) != 2 || roofShade(v3{-0.5, 0.5, 0.7}) != 3 || roofShade(v3{0.6, -0.6, 0.5}) != 0 {
		t.Fatal("shade buckets")
	}
}

func TestFitAffine(t *testing.T) {
	var src, dst []geo.Pt
	for i := 0; i < 5; i++ {
		for j := 0; j < 5; j++ {
			p := geo.Pt{X: -745000 + float64(i)*600, Y: -1044000 + float64(j)*500}
			src = append(src, p)
			dst = append(dst, geo.Pt{X: 0.99*p.X - 0.13*p.Y + 1e-7*p.X*p.X + 5, Y: 0.13*p.X + 0.99*p.Y - 7})
		}
	}
	af, err := fitAffinePts(src, dst)
	if err != nil || af.residual > 1e-3 {
		t.Fatalf("fit %v residual %v", err, af.residual)
	}
}

func TestModelReplaces(t *testing.T) {
	// A 20 × 20 m roof (two triangles) plus a wall that projects to a line.
	part := &pb.ModelPart{Positions: []int32{0, 0, 100, 200, 0, 100, 200, 200, 100, 0, 200, 100, 0, 0, 0},
		Triangles: []uint32{0, 1, 2, 0, 2, 3, 0, 4, 1}}
	m := &pb.Model{Parts: []*pb.ModelPart{part}}
	b := func(x0, x1 int32, lm uint32) *pb.Building {
		return &pb.Building{Rings: []int32{x0, 0, x1, 0, x1, 100, x0, 100}, RingEnds: []uint32{4}, Landmark: lm}
	}
	chunks := map[[2]int]*pb.Chunk{{0, 0}: {Buildings: []*pb.Building{b(0, 100, 0), b(150, 250, 0), b(300, 400, 0), b(500, 600, 7)}}}
	got := modelReplaces(m, chunks, 0.6, 7)
	if len(got) != 2 || got[0].Index != 0 || got[1].Index != 3 {
		t.Fatalf("replaces %+v, want buildings 0 and 3 (the second is 50 %% covered, the last is the landmark)", got)
	}
}

// v4 `parts`: an override picks the smallest group box around its point (a tower part of a larger
// building), the rest of the building keeps its roles.
func TestBuildPartPartRoles(t *testing.T) {
	b := box("_m", 0, 0, 20, 10, 0, false)
	tw := box("_m", 30, 0, 4, 30, 0, true)
	b.Groups = append(b.Groups, tw.Groups[0])
	for _, p := range tw.Polys {
		if p.Kind == citygml.Ground {
			continue
		}
		p.Group = 1
		b.Polys = append(b.Polys, p)
	}
	mc := config.ModelConfig{Parts: []config.PartRole{{Walls: "stone", Roof: "slate", XY: [2]float64{32, 2}}}}
	part, _ := buildPart(b, mc, copperRule{}, 1.5, 0.1, nil, 1)
	count := map[pb.ModelRole]int{}
	for _, x := range part.Roles {
		count[pb.ModelRole(x)]++
	}
	if count[pb.ModelRole_ROLE_SLATE] != 2 || count[pb.ModelRole_ROLE_STONE] != 8 || count[pb.ModelRole_ROLE_ROOF] != 2 ||
		count[pb.ModelRole_ROLE_WALL] != 8 || count[pb.ModelRole_ROLE_COPPER] != 0 {
		t.Fatalf("roles %v: want slate 2, stone 8 (tower), roof 2, wall 8 (block)", count)
	}
}

// v4: a ground polygon far above the foot (the underside of a pod) is not the foot.
func TestBuildPartFloatingGround(t *testing.T) {
	b := box("_z", 0, 0, 10, 120, 250, false)
	pod := []citygml.V3{{X: 30, Y: 30, Z: 330}, {X: 30, Y: 40, Z: 330}, {X: 40, Y: 40, Z: 330}, {X: 40, Y: 30, Z: 330}}
	b.Polys = append(b.Polys, citygml.Poly{Kind: citygml.Ground, Rings: [][]citygml.V3{pod}})
	part, _ := buildPart(b, config.ModelConfig{}, copperRule{groundFloat: 20}, 1.5, 0.1, flatTerrain(30), 2)
	if part.AnchorX != 50 || part.AnchorY != 50 || part.BaseZDm != 300 {
		t.Fatalf("anchor (%d, %d) base %d dm, want (50, 50) and 300 (the pod is not the foot)", part.AnchorX, part.AnchorY, part.BaseZDm)
	}
}

// v6: a `drop` ring removes the polygons whose vertex mean lies inside it; a wall on the ring's
// edge stays, the source building shared with another model is not touched.
func TestDropPolys(t *testing.T) {
	e := &Env{Proj: geo.NewProjection(40.758, -73.9855)}
	tower := box("t", 0, 0, 10, 100, 0, false)
	annex := box("t", 10, 0, 10, 8, 0, false) // same id: one source object (NYC, one BIN)
	b := &srcBuilding{ID: "t", Groups: tower.Groups, C: tower.C, Polys: append(append([]citygml.Poly(nil), tower.Polys...), annex.Polys...)}
	lon := func(x float64) float64 { lo, _ := e.Proj.Inverse(geo.Pt{X: x}); return lo }
	lat := func(y float64) float64 { _, la := e.Proj.Inverse(geo.Pt{Y: y}); return la }
	ring := [][2]float64{{lon(10.5), lat(-5)}, {lon(30), lat(-5)}, {lon(30), lat(15)}, {lon(10.5), lat(15)}}
	out := e.dropPolys("x", []*srcBuilding{b}, [][][2]float64{ring})
	if got, want := len(out[0].Polys), len(tower.Polys)+1; got != want {
		// the annex keeps only its west wall (x = 10, on the tower's east face)
		t.Fatalf("polys = %d, want %d", got, want)
	}
	if len(b.Polys) != len(tower.Polys)+len(annex.Polys) {
		t.Fatalf("source building changed: %d polys", len(b.Polys))
	}
}

// v6: NYC heights are US survey feet; usFootM is exact.
func TestUSFoot(t *testing.T) {
	if math.Abs(usFootM*3937-1200) > 1e-9 || modelSources["nyc_3d"].zScale != usFootM || modelSources["nyc_3d"].srs != "EPSG:2263" {
		t.Fatalf("nyc_3d source: %+v", modelSources["nyc_3d"])
	}
}
