package steps

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"citypack/internal/geo"
	"citypack/internal/pb"
)

func TestSlicePolyline(t *testing.T) {
	pts := []geo.Pt{{X: 0, Y: 0}, {X: 10, Y: 0}, {X: 10, Y: 10}}
	cum := []float64{0, 10, 20}
	got := slicePolyline(pts, cum, 5, 15)
	want := []geo.Pt{{X: 5, Y: 0}, {X: 10, Y: 0}, {X: 10, Y: 5}}
	if len(got) != len(want) {
		t.Fatalf("got %v", got)
	}
	for i := range want {
		if got[i].Dist(want[i]) > 1e-9 {
			t.Fatalf("got %v, want %v", got, want)
		}
	}
}

func TestOneway(t *testing.T) {
	back, fwd := "backward", "forward"
	s := rawSegment{Access: []accessRule{{Type: "denied", When: &accessWhen{Heading: &back}}}}
	if s.oneway() != 1 {
		t.Fatal("denied backward must be one-way forward")
	}
	s.Access[0].When.Heading = &fwd
	if s.oneway() != -1 {
		t.Fatal("denied forward must be one-way backward")
	}
	s.Access[0].When.Mode = []string{"bicycle"}
	if s.oneway() != 0 {
		t.Fatal("mode-specific restriction must not make a one-way")
	}
}

// A square area with a road crossing its east border and an isolated stray edge.
func testGraph() *workGraph {
	return &workGraph{
		nodes:  []geo.Pt{{X: 0, Y: 0}, {X: 50, Y: 0}, {X: 150, Y: 0}, {X: 0, Y: 50}, {X: 80, Y: 80}, {X: 90, Y: 80}},
		border: make([]bool, 6),
		edges: []workEdge{
			{from: 0, to: 1, pts: []geo.Pt{{X: 0, Y: 0}, {X: 50, Y: 0}}, class: pb.RoadClass_PRIMARY},
			{from: 1, to: 2, pts: []geo.Pt{{X: 50, Y: 0}, {X: 150, Y: 0}}, class: pb.RoadClass_PRIMARY},
			{from: 0, to: 3, pts: []geo.Pt{{X: 0, Y: 0}, {X: 0, Y: 50}}, class: pb.RoadClass_RESIDENTIAL},
			{from: 4, to: 5, pts: []geo.Pt{{X: 80, Y: 80}, {X: 90, Y: 80}}, class: pb.RoadClass_RESIDENTIAL},
		},
	}
}

func TestClipToAreaMakesBorderNode(t *testing.T) {
	area := []geo.Pt{{X: -10, Y: -10}, {X: 100, Y: -10}, {X: 100, Y: 100}, {X: -10, Y: 100}}
	g := clipToArea(testGraph(), area)
	if len(g.edges) != 4 {
		t.Fatalf("edges %d", len(g.edges))
	}
	cut := g.edges[1]
	end := cut.pts[len(cut.pts)-1]
	if end.Dist(geo.Pt{X: 100, Y: 0}) > 1e-9 || !g.border[cut.to] {
		t.Fatalf("crossing edge must end on the border at a border node, got %v", end)
	}
}

func TestLargestComponentAndConnectKept(t *testing.T) {
	g := largestComponent(testGraph())
	if len(g.edges) != 3 {
		t.Fatalf("stray edge should be dropped, %d edges", len(g.edges))
	}
	// Two kept pieces joined only through the residential street.
	g = &workGraph{
		nodes:  []geo.Pt{{X: 0, Y: 0}, {X: 10, Y: 0}, {X: 10, Y: 10}, {X: 20, Y: 10}},
		border: make([]bool, 4),
		edges: []workEdge{
			{from: 0, to: 1, pts: []geo.Pt{{X: 0, Y: 0}, {X: 10, Y: 0}}, kept: true},
			{from: 1, to: 2, pts: []geo.Pt{{X: 10, Y: 0}, {X: 10, Y: 10}}},
			{from: 2, to: 3, pts: []geo.Pt{{X: 10, Y: 10}, {X: 20, Y: 10}}, kept: true},
		},
	}
	connectKept(g)
	if !g.edges[1].kept {
		t.Fatal("connector alley must be promoted")
	}
}

func TestReachableRespectsOneway(t *testing.T) {
	g := &pb.Graph{
		Nodes: []*pb.Node{{}, {}, {}},
		Edges: []*pb.Edge{
			{From: 0, To: 1, Kept: true},
			{From: 1, To: 2, Kept: true, Oneway: -1}, // only 2 → 1
		},
	}
	r := reachable(g, 0)
	if !r[1] || r[2] {
		t.Fatalf("reach %v", r)
	}
}

func TestTarballIsDeterministicAndRoundTrips(t *testing.T) {
	dir := t.TempDir()
	for name, body := range map[string]string{"manifest.pb": "m", "chunks/0_0.pb": "c"} {
		p := dir + "/" + name
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	a, err := Tarball(dir)
	if err != nil {
		t.Fatal(err)
	}
	b, _ := Tarball(dir)
	if !bytes.Equal(a, b) {
		t.Fatal("tarball must be byte-identical for the same input")
	}
	out := t.TempDir()
	if err := Untar(a, out); err != nil {
		t.Fatal(err)
	}
	if got, _ := os.ReadFile(out + "/chunks/0_0.pb"); string(got) != "c" {
		t.Fatalf("round trip: %q", got)
	}
}
