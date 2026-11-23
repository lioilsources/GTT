package steps

import (
	"testing"

	"citypack/internal/pb"
)

func steepPack(edges ...*pb.Edge) *PackData {
	return &PackData{
		Manifest: &pb.Manifest{Exaggeration: 2},
		Graph:    &pb.Graph{Names: []string{"", "Flat", "Steep", "Short"}, Edges: edges},
	}
}

// line builds an edge along x with heights zs (game dm) every step metres.
func line(name uint32, step int32, zs ...int32) *pb.Edge {
	ed := &pb.Edge{Name: name}
	for i, z := range zs {
		ed.Points = append(ed.Points, int32(i)*step*10, 0)
		ed.ZDm = append(ed.ZDm, z)
	}
	return ed
}

func TestSteepestStreets(t *testing.T) {
	p := steepPack(
		line(1, 20, 0, 0, 0, 0, 0),
		// 2 m game per 20 m = 10 % game = 5 % real, over 80 m.
		line(2, 20, 0, 20, 40, 60, 80),
		// 20 m long: shorter than 2/3 of the window, skipped.
		line(3, 10, 0, 50, 100),
		// Tunnels and unnamed edges never count.
		func() *pb.Edge { e := line(2, 20, 0, 200, 400, 600); e.Tunnel = true; return e }(),
		line(0, 20, 0, 200, 400, 600),
	)
	got := steepestStreets(p, 10)
	if len(got) != 2 {
		t.Fatalf("got %d streets, want 2: %+v", len(got), got)
	}
	if got[0].Name != "Steep" || got[0].GradePct != 5 || got[0].LengthM != 60 {
		t.Fatalf("steepest = %+v, want Steep 5 %% over 60 m", got[0])
	}
	if got[1].Name != "Flat" || got[1].GradePct != 0 {
		t.Fatalf("second = %+v, want Flat 0 %%", got[1])
	}
}

func TestGroundEdge(t *testing.T) {
	for _, c := range []struct {
		ed   *pb.Edge
		want bool
	}{
		{&pb.Edge{}, true},
		{&pb.Edge{LayerFrom: -1, LayerTo: -1}, true}, // sunken, not a tunnel: on the terrain
		{&pb.Edge{LayerFrom: -1, LayerTo: -1, Tunnel: true}, false},
		{&pb.Edge{LayerFrom: 1, LayerTo: 1, Bridge: true}, false},
		{&pb.Edge{LayerFrom: 0, LayerTo: 1}, false},
	} {
		if got := groundEdge(c.ed); got != c.want {
			t.Errorf("groundEdge(%+v) = %v, want %v", c.ed, got, c.want)
		}
	}
}
