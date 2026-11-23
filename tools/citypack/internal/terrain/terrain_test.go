package terrain

import (
	"encoding/json"
	"flag"
	"math"
	"os"
	"path/filepath"
	"testing"

	"citypack/internal/geo"
)

var update = flag.Bool("update", false, "rewrite testdata/*.golden.json")

// params are the content/tuning.yaml defaults of `terrain` (plan 3.2) with the profile window
// of lidar data.
func params() Params {
	return Params{
		Exaggeration: 2,
		MaxGrade:     map[string]float64{"motorway": 0.08, "trunk": 0.10, "primary": 0.20, "secondary": 0.20, "tertiary": 0.28, "alley": 0.33},
		ClearWaterM:  15, ClearRoadM: 6, BridgeGrade: 0.07,
		DepthWaterM: 10, DepthLandM: 8, TunnelGrade: 0.07,
		StepM: 16, WindowM: 40, ElevatedM: 8, GradeTolM: 0.05, GradePasses: 500, ZTolM: 0.1,
	}
}

// scene is a synthetic network over an analytic terrain.
type scene struct {
	name    string
	ground  func(geo.Pt) float64
	water   func(geo.Pt) (float64, bool)
	nodes   []geo.Pt
	edges   []Edge
	z0      float64
	extentM float64
}

func dry(geo.Pt) (float64, bool) { return 0, false }

// line builds a chain of edges along x at y with nodes every step metres.
func line(s *scene, x0, x1, y, step float64, class string, layer func(x float64) int) {
	first := len(s.nodes)
	for x := x0; x <= x1+1e-9; x += step {
		s.nodes = append(s.nodes, geo.Pt{X: x, Y: y})
	}
	for k := first + 1; k < len(s.nodes); k++ {
		a, b := s.nodes[k-1], s.nodes[k]
		s.edges = append(s.edges, Edge{From: k - 1, To: k, Pts: []geo.Pt{a, b}, Class: class,
			LayerFrom: layer(a.X + 1e-6), LayerTo: layer(b.X - 1e-6), HalfWidthM: 9, Bridge: layer(a.X+1e-6)+layer(b.X-1e-6) > 0})
	}
}

func flatLayer(float64) int { return 0 }

func scenes() []scene {
	var out []scene
	// Plane: everything sits at z0, nothing is clamped.
	plane := scene{name: "plane", ground: func(geo.Pt) float64 { return 12 }, water: dry, z0: 12, extentM: 512}
	line(&plane, -200, 200, 0, 100, "primary", flatLayer)
	line(&plane, -200, 200, 120, 50, "alley", flatLayer)
	out = append(out, plane)

	// Cone: 15 % real slope = 30 % game; primary (20 %) is clamped, an alley (33 %) is not.
	cone := scene{name: "cone", ground: func(p geo.Pt) float64 { return math.Max(0, 60-0.15*p.Len()) }, water: dry, extentM: 512}
	line(&cone, -400, 400, 0, 100, "primary", flatLayer)
	line(&cone, -400, 400, 40, 100, "alley", flatLayer)
	out = append(out, cone)

	// Ridge: a 40 m Gaussian ridge along y, crossed by a motorway (8 %) – long cuts and fills.
	ridge := scene{name: "ridge", ground: func(p geo.Pt) float64 { return 40 * math.Exp(-p.X*p.X/(2*80*80)) }, water: dry, extentM: 512}
	line(&ridge, -480, 480, 0, 160, "motorway", flatLayer)
	out = append(out, ridge)

	// Valley with a river and a bridge: banks at 30 m, river 40 m wide at level 0.
	valley := scene{
		name:   "valley_bridge",
		ground: func(p geo.Pt) float64 { return 30 - 30*math.Exp(-p.X*p.X/(2*60*60)) },
		water: func(p geo.Pt) (float64, bool) {
			return 0, math.Abs(p.X) < 20
		},
		extentM: 512,
	}
	line(&valley, -480, 480, 0, 80, "primary", func(x float64) int {
		if math.Abs(x) < 160 {
			return 1
		}
		return 0
	})
	// A riverside road crossing under the bridge (north–south at x = 30, on the bank).
	first := len(valley.nodes)
	for y := -120.0; y <= 120; y += 60 {
		valley.nodes = append(valley.nodes, geo.Pt{X: 30, Y: y})
	}
	for k := first + 1; k < len(valley.nodes); k++ {
		valley.edges = append(valley.edges, Edge{From: k - 1, To: k, Pts: []geo.Pt{valley.nodes[k-1], valley.nodes[k]}, Class: "tertiary", HalfWidthM: 9})
	}
	out = append(out, valley)
	return out
}

type golden struct {
	NodeDM   []int32   `json:"node_dm"`
	EdgeDM   [][]int32 `json:"edge_dm"`
	EdgeN    []int     `json:"edge_vertices"`
	Stairs   []bool    `json:"stairs"`
	Clamped  int       `json:"clamped"`
	Terrain  [][]int32 `json:"terrain_dm_row0"`
	Residual float64   `json:"residual_m"`
}

func run(s scene) (Result, *Raster) {
	p := params()
	in := Input{Nodes: s.nodes, Edges: s.edges, Ground: s.ground, Water: s.water, Z0: s.z0}
	res := Profile(in, p)
	var roads []Road
	for ei, pts := range res.EdgePts {
		for k := 1; k < len(pts); k++ {
			if res.GroundPt[ei][k-1] && res.GroundPt[ei][k] {
				roads = append(roads, Road{A: pts[k-1], B: pts[k], ZA: res.EdgeZ[ei][k-1], ZB: res.EdgeZ[ei][k], HalfWidthM: s.edges[ei].HalfWidthM})
			}
		}
	}
	n := int(2*s.extentM/8) + 1
	r := NewRaster(-s.extentM, -s.extentM, 8, n, n)
	Conform(r, func(q geo.Pt) float64 { return (s.ground(q) - s.z0) * p.Exaggeration },
		func(q geo.Pt) (float64, bool) {
			l, ok := s.water(q)
			return (l - s.z0) * p.Exaggeration, ok
		}, roads, ConformParams{SupportM: 8, BlendM: 24, UnderwaterM: 3})
	return res, r
}

func TestGoldenScenes(t *testing.T) {
	for _, s := range scenes() {
		t.Run(s.name, func(t *testing.T) {
			res, r := run(s)
			g := golden{Stairs: res.Stairs, Clamped: res.Clamped, Residual: math.Round(res.Residual*1000) / 1000}
			for _, z := range res.NodeZ {
				g.NodeDM = append(g.NodeDM, geo.DM(z))
			}
			for ei := range res.EdgeZ {
				var row []int32
				for _, z := range res.EdgeZ[ei] {
					row = append(row, geo.DM(z))
				}
				g.EdgeDM = append(g.EdgeDM, row)
				g.EdgeN = append(g.EdgeN, len(res.EdgePts[ei]))
			}
			// The terrain along the row through y = 0 and a row 40 m north of the roads.
			for _, y := range []float64{0, 72} {
				j := int((y - r.Y0) / r.Step)
				var row []int32
				for i := 0; i < r.W; i += 4 {
					row = append(row, geo.DM(r.At(i, j)))
				}
				g.Terrain = append(g.Terrain, row)
			}
			b, _ := json.MarshalIndent(g, "", " ")
			path := filepath.Join("testdata", s.name+".golden.json")
			if *update {
				_ = os.MkdirAll("testdata", 0o755)
				if err := os.WriteFile(path, b, 0o644); err != nil {
					t.Fatal(err)
				}
				return
			}
			want, err := os.ReadFile(path)
			if err != nil {
				t.Fatalf("%v (run go test ./internal/terrain -update)", err)
			}
			if string(want) != string(b) {
				t.Errorf("%s differs from golden output; inspect and rerun with -update if intended", path)
			}
		})
	}
}

// Invariants that must hold for every scene regardless of the golden numbers.
func TestScenesKeepGradesAndClearances(t *testing.T) {
	p := params()
	for _, s := range scenes() {
		res, r := run(s)
		for ei, e := range s.edges {
			if res.Stairs[ei] {
				t.Errorf("%s: edge %d became stairs", s.name, ei)
				continue
			}
			g := grade(p, e.Class)
			if e.LayerFrom != 0 || e.LayerTo != 0 {
				g = math.Min(g, p.BridgeGrade)
			}
			pts, zs := res.EdgePts[ei], res.EdgeZ[ei]
			if pts[0] != s.nodes[e.From] || pts[len(pts)-1] != s.nodes[e.To] {
				t.Fatalf("%s: edge %d lost its end nodes", s.name, ei)
			}
			if math.Abs(zs[0]-res.NodeZ[e.From]) > 1e-9 || math.Abs(zs[len(zs)-1]-res.NodeZ[e.To]) > 1e-9 {
				t.Errorf("%s: edge %d ends disagree with node heights", s.name, ei)
			}
			for k := 1; k < len(pts); k++ {
				l := pts[k].Dist(pts[k-1])
				if gr := math.Abs(zs[k]-zs[k-1]) / l; gr > g+0.002 {
					t.Errorf("%s: edge %d grade %.3f over %.3f", s.name, ei, gr, g)
				}
			}
			// Road surface and terrain agree at the corridor edge on ground edges.
			if e.LayerFrom == 0 && e.LayerTo == 0 {
				for k := 1; k < len(pts); k++ {
					a, b := pts[k-1], pts[k]
					dir := b.Sub(a).Mul(1 / a.Dist(b))
					nrm := geo.Pt{X: -dir.Y, Y: dir.X}
					for _, t0 := range []float64{0.25, 0.5, 0.75} {
						c := a.Add(b.Sub(a).Mul(t0))
						z := zs[k-1] + (zs[k]-zs[k-1])*t0
						for _, side := range []float64{-1, 1} {
							q := c.Add(nrm.Mul(side * e.HalfWidthM))
							if d := math.Abs(r.Bilinear(q) - z); d > 0.3 {
								t.Errorf("%s: edge %d road edge %.2f m from terrain", s.name, ei, d)
							}
						}
					}
				}
			}
		}
	}
	// The bridge clears the river by clear_water_m and the bank road by clear_road_m.
	v := scenes()[3]
	res, _ := run(v)
	road := res.NodeZ[len(v.nodes)-3] // the riverside road where it passes under the deck (y = 0)
	for ei, e := range v.edges {
		if e.LayerFrom != 1 && e.LayerTo != 1 {
			continue
		}
		for k, q := range res.EdgePts[ei] {
			if math.Abs(q.X) < 20 && res.EdgeZ[ei][k] < 15-0.05 {
				t.Errorf("deck at x=%.0f is %.2f m, want ≥ 15 above the river", q.X, res.EdgeZ[ei][k])
			}
			if math.Abs(q.X-30) < 9 && res.EdgeZ[ei][k] < road+6-0.05 {
				t.Errorf("deck at x=%.0f is %.2f m over a road at %.2f m, want ≥ 6 clearance", q.X, res.EdgeZ[ei][k], road)
			}
		}
	}
}

func TestFillAndBlur(t *testing.T) {
	r := NewRaster(0, 0, 4, 20, 20)
	mask := make([]bool, len(r.Z))
	for j := 0; j < 20; j++ {
		for i := 0; i < 20; i++ {
			r.Set(i, j, float64(i))
			if i > 5 && i < 12 && j > 5 && j < 12 {
				r.Set(i, j, 500) // a building in a bare-earth-less surface model
				mask[j*20+i] = true
			}
		}
	}
	r.Fill(mask)
	for j := 6; j < 12; j++ {
		for i := 6; i < 12; i++ {
			if math.Abs(r.At(i, j)-float64(i)) > 1.5 {
				t.Fatalf("filled (%d,%d) = %.2f, want about %d", i, j, r.At(i, j), i)
			}
		}
	}
	r.Blur(30)
	if v := r.At(10, 10); math.Abs(v-10) > 2 {
		t.Errorf("blurred ramp at 10 = %.2f", v)
	}
}

func TestShadeFlatIs128(t *testing.T) {
	r := NewRaster(0, 0, 8, 5, 5)
	for _, v := range r.Shade(315, 45) {
		if v != 128 {
			t.Fatalf("flat shade %d, want 128", v)
		}
	}
	// A slope rising to the south-east faces the north-west sun: brighter than flat.
	for j := 0; j < 5; j++ {
		for i := 0; i < 5; i++ {
			r.Set(i, j, float64(i)-float64(j)) // up to the east and to the south
		}
	}
	if v := r.Shade(315, 45)[2*5+2]; v <= 128 {
		t.Errorf("north-west facing slope shade %d, want > 128", v)
	}
}
