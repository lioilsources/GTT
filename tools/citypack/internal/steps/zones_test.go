package steps

import (
	"testing"

	"citypack/internal/pb"
)

func TestBarrierRoadCrossings(t *testing.T) {
	p := &PackData{
		Graph: &pb.Graph{Names: []string{""}, Edges: []*pb.Edge{
			{Points: []int32{0, 0, 1000, 0}}, // road along y = 0 from x = 0 to 100 m
		}},
		Chunks: []*pb.Chunk{{Barriers: []*pb.Barrier{
			{Points: []int32{0, 50, 1000, 50}},   // curb line beside the road: fine
			{Points: []int32{500, -50, 500, 50}}, // across the road: bad
		}}},
	}
	if n := barrierRoadCrossings(p); n != 1 {
		t.Fatalf("crossings = %d, want 1", n)
	}
	p.Chunks[0].Barriers = p.Chunks[0].Barriers[:1]
	if n := barrierRoadCrossings(p); n != 0 {
		t.Fatalf("crossings = %d, want 0", n)
	}
}
