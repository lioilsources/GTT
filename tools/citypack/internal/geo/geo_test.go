package geo

import (
	"math"
	"testing"
)

func TestProjectionRoundTrip(t *testing.T) {
	p := NewProjection(40.758, -73.9855)
	q := p.Forward(-73.9855, 40.759)
	if math.Abs(q.X) > 1e-6 || math.Abs(q.Y-111.195) > 0.01 {
		t.Fatalf("0.001° north = %v, want (0, 111.195)", q)
	}
	lon, lat := p.Inverse(p.Forward(-73.97, 40.75))
	if math.Abs(lon+73.97) > 1e-9 || math.Abs(lat-40.75) > 1e-9 {
		t.Fatalf("round trip %f %f", lon, lat)
	}
}

func TestPointInRingAndOrient(t *testing.T) {
	sq := []Pt{{0, 0}, {10, 0}, {10, 10}, {0, 10}}
	if !PointInRing(Pt{5, 5}, sq) || PointInRing(Pt{15, 5}, sq) {
		t.Fatal("point in ring")
	}
	if SignedArea(sq) != 100 {
		t.Fatalf("area %f", SignedArea(sq))
	}
	if SignedArea(Orient(sq, false)) != -100 {
		t.Fatal("orient cw")
	}
}

func TestTriangulateWithHole(t *testing.T) {
	outer := []Pt{{0, 0}, {10, 0}, {10, 10}, {0, 10}}
	hole := []Pt{{4, 4}, {4, 6}, {6, 6}, {6, 4}}
	idx, err := Triangulate([][]Pt{outer, hole})
	if err != nil {
		t.Fatal(err)
	}
	all := append(append([]Pt{}, outer...), hole...)
	area := 0.0
	for i := 0; i < len(idx); i += 3 {
		a, b, c := all[idx[i]], all[idx[i+1]], all[idx[i+2]]
		area += math.Abs(b.Sub(a).Cross(c.Sub(a))) / 2
	}
	if math.Abs(area-96) > 1e-9 {
		t.Fatalf("triangulated area %f, want 96", area)
	}
}

func TestOpenRing(t *testing.T) {
	r := OpenRing([]Pt{{0, 0}, {1, 0}, {1, 0}, {1, 1}, {0, 0}})
	if len(r) != 3 {
		t.Fatalf("got %v", r)
	}
}
