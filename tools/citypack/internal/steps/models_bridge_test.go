package steps

import (
	"math"
	"testing"

	"citypack/internal/citygml"
	"citypack/internal/config"
	"citypack/internal/pb"
)

func TestParsePolygonZ(t *testing.T) {
	r, err := parsePolygonZ("POLYGON Z ((0 0 1, 4 0 1, 4 4 1, 0 4 1, 0 0 1), (1 1 1, 2 1 1, 2 2 1, 1 1 1))")
	if err != nil {
		t.Fatal(err)
	}
	if len(r) != 2 || len(r[0]) != 4 || len(r[1]) != 3 || r[0][2] != (citygml.V3{X: 4, Y: 4, Z: 1}) {
		t.Fatalf("rings %v", r)
	}
	for _, bad := range []string{"POLYGON ((0 0, 1 0, 1 1, 0 0))", "POLYGON Z ((0 0 0, 1 0 0, 0 0 0))", "MULTIPOLYGON Z (((0 0 0, 1 0 0, 1 1 0, 0 0 0)))"} {
		if _, err := parsePolygonZ(bad); err == nil {
			t.Errorf("%q: no error", bad)
		}
	}
}

func TestSurfaceRoleTowers(t *testing.T) {
	mc := config.ModelConfig{Roles: map[string]string{"_t": "slate"}, Towers: map[string]string{"_t": "slate"}}
	if got := surfaceRole(citygml.Roof, mc, "_t", "", true, false); got != pb.ModelRole_ROLE_SLATE {
		t.Errorf("tower roof with towers override: %v", got)
	}
	if got := surfaceRole(citygml.Roof, mc, "_t", "", false, true); got != pb.ModelRole_ROLE_SLATE {
		t.Errorf("slender roof with towers override: %v", got)
	}
	if got := surfaceRole(citygml.Roof, mc, "_o", "", true, false); got != pb.ModelRole_ROLE_COPPER {
		t.Errorf("other building keeps copper: %v", got)
	}
	if got := surfaceRole(citygml.Wall, mc, "_t", "", true, false); got != pb.ModelRole_ROLE_WALL {
		t.Errorf("towers map does not touch walls: %v", got)
	}
}

// testBridge is a 100 m bridge along x: a deck at z 10 (clockwise ring, as the shapefile),
// two side walls from z 0 and a pier top at z 2 (horizontal, far below the deck).
func testBridge() *srcBuilding {
	b := &srcBuilding{ID: "bridge:1", Bridge: true, Groups: []citygml.Group{{ID: "bridge:1", Usage: "bridge"}}}
	poly := func(vs ...citygml.V3) { b.Polys = append(b.Polys, citygml.Poly{Rings: [][]citygml.V3{vs}}) }
	poly(citygml.V3{X: 0, Y: 0, Z: 10}, citygml.V3{X: 0, Y: 8, Z: 10}, citygml.V3{X: 100, Y: 8, Z: 10}, citygml.V3{X: 100, Y: 0, Z: 10})
	for _, y := range []float64{0, 8} {
		poly(citygml.V3{X: 0, Y: y, Z: 0}, citygml.V3{X: 100, Y: y, Z: 0}, citygml.V3{X: 100, Y: y, Z: 10}, citygml.V3{X: 0, Y: y, Z: 10})
	}
	poly(citygml.V3{X: 45, Y: 0, Z: 2}, citygml.V3{X: 55, Y: 0, Z: 2}, citygml.V3{X: 55, Y: 8, Z: 2}, citygml.V3{X: 45, Y: 8, Z: 2})
	return b
}

// slopeTerrain rises along x: z = z0 + k·x.
func slopeTerrain(z0, k float64) *TerrainGrid {
	t := &TerrainGrid{CX0: -2, CY0: -2, W: 129, H: 129, Step: 8, ChunkM: 256, Z: make([]int16, 129*129)}
	for j := 0; j < t.H; j++ {
		for i := 0; i < t.W; i++ {
			x := float64(t.CX0)*t.ChunkM + float64(i)*t.Step
			t.Z[j*t.W+i] = int16(math.Round((z0 + k*x) * 10))
		}
	}
	return t
}

func TestBuildBridgePart(t *testing.T) {
	// Ends: terrain 20 at x = 0, 30 at x = 100 (exaggerated banks differ).
	part, plan := buildBridgePart(testBridge(), config.ModelConfig{}, 1.5, 0.1, 15, slopeTerrain(20, 0.1))
	if part == nil {
		t.Fatal("no part")
	}
	if part.BaseZDm != 300 {
		t.Errorf("base_z %d dm, want 300 (the higher end)", part.BaseZDm)
	}
	ax, ay := float64(part.AnchorX)/10, float64(part.AnchorY)/10
	for i := 0; i+2 < len(part.Positions); i += 3 {
		if z := float64(part.Positions[i+2]) / 10; z > 0 {
			t.Errorf("vertex (%.1f, %.1f) at z %.1f > 0", ax+float64(part.Positions[i])/10, ay+float64(part.Positions[i+1])/10, z)
		}
	}
	deckZ := map[float64]float64{}
	walls, flats := 0, 0
	for k := 0; k+2 < len(part.Triangles); k += 3 {
		v := func(i uint32) v3 {
			return v3{float64(part.Positions[3*i]) / 10, float64(part.Positions[3*i+1]) / 10, float64(part.Positions[3*i+2]) / 10}
		}
		a, b, c := v(part.Triangles[k]), v(part.Triangles[k+1]), v(part.Triangles[k+2])
		n := b.sub(a).cross(c.sub(a))
		if part.Surfaces[k/3] != byte(pb.ModelSurface_SURFACE_ROOF) {
			t.Errorf("triangle %d: surface %d, bridges have SURFACE_ROOF", k/3, part.Surfaces[k/3])
		}
		if math.Abs(n.z)/n.norm() > 0.9 {
			flats++
			if n.z < 0 {
				t.Errorf("horizontal triangle %d faces down", k/3)
			}
			for _, w := range []v3{a, b, c} {
				if x := math.Round(ax + w.x); x == 0 || x == 100 { // deck ends, not the pier top
					deckZ[x] = float64(part.BaseZDm)/10 + w.z
				}
			}
		} else {
			walls++
		}
	}
	if walls != 8 {
		t.Errorf("%d wall triangles, want 8 (two quads, both sides)", walls)
	}
	if flats != 4 {
		t.Errorf("%d horizontal triangles, want 4 (deck and pier top, one side)", flats)
	}
	if math.Abs(deckZ[0]-20) > 0.15 || math.Abs(deckZ[100]-30) > 0.15 {
		t.Errorf("deck at the ends %.2f / %.2f, want 20 / 30 (on the terrain)", deckZ[0], deckZ[100])
	}
	if len(plan) != 2 {
		t.Errorf("plan %d polygons, want 2", len(plan))
	}
}

func TestClipBridgeRoads(t *testing.T) {
	part, _ := buildBridgePart(testBridge(), config.ModelConfig{}, 1.5, 0.1, 15, slopeTerrain(20, 0))
	// The deck is at 20 everywhere. A lane crossing under it at x = 50.
	lane := func(z float64) *pb.Graph {
		return &pb.Graph{Names: []string{""}, Edges: []*pb.Edge{{
			Points: []int32{500, -200, 500, 280}, ZDm: []int32{int32(z * 10), int32(z * 10)}, WidthM: 4,
		}}}
	}
	if h := bridgeRoadClash(part, lane(5), 4.5, 0.3, nil); h.n != 0 {
		t.Errorf("lane 15 m below the deck (7 m below the pier top): %d clashes", h.n)
	}
	if h := bridgeRoadClash(part, lane(10), 4.5, 0.3, nil); h.n == 0 {
		t.Error("lane 2 m below the pier top: no clash")
	}
	if h := bridgeRoadClash(part, lane(17), 4.5, 0.3, nil); h.n == 0 {
		t.Error("lane 3 m below the deck: no clash")
	}
	if h := bridgeRoadClash(part, lane(20.1), 4.5, 0.3, nil); h.n == 0 {
		t.Error("lane at the deck (depth fight): no clash")
	}
	if h := bridgeRoadClash(part, lane(21), 4.5, 0.3, nil); h.n != 0 {
		t.Errorf("lane 1 m above the deck: %d clashes", h.n)
	}
	before := len(part.Roles)
	n := clipBridgeRoads(part, lane(17), 4.5, 0.3)
	if n == 0 || len(part.Roles) != before-n || len(part.Triangles) != 3*len(part.Roles) || len(part.Surfaces) != len(part.Roles) {
		t.Fatalf("clipped %d of %d: %d indices, %d roles, %d surfaces", n, before, len(part.Triangles), len(part.Roles), len(part.Surfaces))
	}
	if h := bridgeRoadClash(part, lane(17), 4.5, 0.3, nil); h.n != 0 {
		t.Errorf("after clipping: %d clashes", h.n)
	}
}
