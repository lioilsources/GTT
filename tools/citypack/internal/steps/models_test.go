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
	part, plan := buildPart(box("_b", 0, 0, 10, 20, 250, false), config.ModelConfig{}, 1.5, 0.1, flatTerrain(30), 2)
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
	if p, _ := buildPart(box("_s", 0, 0, 1, 1, 0, false), config.ModelConfig{}, 1.5, 0.1, nil, 2); p != nil {
		t.Fatal("small part kept")
	}
}

func TestBuildPartRoles(t *testing.T) {
	part, _ := buildPart(box("_t", 0, 0, 4, 30, 0, true), config.ModelConfig{}, 1.5, 0.1, nil, 1)
	if pb.ModelRole(part.Roles[len(part.Roles)-1]) != pb.ModelRole_ROLE_COPPER && pb.ModelRole(part.Roles[0]) != pb.ModelRole_ROLE_COPPER {
		t.Fatal("tower roof is not copper")
	}
	mc := config.ModelConfig{Roles: map[string]string{"_t": "gold"}}
	part, _ = buildPart(box("_t", 0, 0, 4, 30, 0, true), mc, 1.5, 0.1, nil, 1)
	gold := 0
	for _, r := range part.Roles {
		if pb.ModelRole(r) == pb.ModelRole_ROLE_GOLD {
			gold++
		}
	}
	if gold != 2 {
		t.Fatalf("gold roof triangles %d, want 2", gold)
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
	part, _ := buildPart(b, config.ModelConfig{}, 1.5, 0.1, flatTerrain(0), 2)
	maxFoot := int32(0)
	for _, i := range part.Foot {
		maxFoot = max(maxFoot, part.Positions[3*i+2])
	}
	if maxFoot != 20 {
		t.Fatalf("highest foot %d dm, want 20 (1 m source × 2)", maxFoot)
	}
	if part.BaseZDm != -20 {
		t.Fatalf("base %d, want -20: no foot vertex above the flat terrain", part.BaseZDm)
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
