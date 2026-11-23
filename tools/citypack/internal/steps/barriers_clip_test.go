package steps

import (
	"math"
	"testing"

	"citypack/internal/geo"
	"citypack/internal/pb"
)

// A bollard line across a kept road (carriageway 4 m half width) and over a bridge loses the
// pieces on the drive surfaces and keeps the rest.
func TestClipBarriers(t *testing.T) {
	g := &pb.Graph{Edges: []*pb.Edge{
		{Kept: true, WidthM: 18, Points: []int32{0, -1000, 0, 1000}},                                 // x = 0, carriageway ±4 m (sidewalk 5)
		{Bridge: true, LayerFrom: 1, LayerTo: 1, WidthM: 12, Points: []int32{500, -1000, 500, 1000}}, // x = 50, footprint ±6 m
	}}
	ds := newDriveSurfaces(g, 5)
	rows := []BarrierRow{{Pts: []geo.Pt{{X: -20, Y: 0}, {X: 70, Y: 0}}}}
	got := clipBarriers(rows, ds, 1)
	if len(got) != 3 {
		t.Fatalf("got %d pieces, want 3: %+v", len(got), got)
	}
	want := [][2]float64{{-20, -4}, {4, 44}, {56, 70}}
	for i, r := range got {
		a, b := r.Pts[0].X, r.Pts[len(r.Pts)-1].X
		if math.Abs(a-want[i][0]) > 0.3 || math.Abs(b-want[i][1]) > 0.3 {
			t.Errorf("piece %d spans %.2f..%.2f, want %.0f..%.0f", i, a, b, want[i][0], want[i][1])
		}
		for _, p := range r.Pts {
			if ds.inside(p, 0.01) {
				t.Errorf("piece %d point %v on a drive surface", i, p)
			}
		}
	}
}
