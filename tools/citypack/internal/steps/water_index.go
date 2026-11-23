package steps

import (
	"math"

	"citypack/internal/geo"
	"citypack/internal/pb"
)

// waterIndex answers "which water level is here" for the terrain step. It tests the same
// triangles the pack draws (naturePieceMesh), not the rings: the player sees the triangles, and
// where a simplified ring is not simple the two disagree. Edges count as inside, so grid nodes on
// the chunk clip lines see both neighbours; where pieces of two bodies meet (the mouths of
// Čertovka, its level estimated from higher banks) the lower level wins, so a node is never
// above either water surface.
type waterIndex struct {
	pieces []NaturePiece
	lvl    []float64
	tris   []waterTri
	grid   map[[2]int][]int
}

type waterTri struct {
	a, b, c geo.Pt
	piece   int
}

func newWaterIndex(water []NaturePiece, levels map[string]float64) *waterIndex {
	wi := &waterIndex{pieces: water, grid: map[[2]int][]int{}}
	for i, w := range water {
		wi.lvl = append(wi.lvl, levels[waterKey(w, i)])
		m, ok := naturePieceMesh(w, pb.GroundKind_WATER)
		if !ok {
			continue
		}
		v := func(k uint32) geo.Pt {
			return geo.Pt{X: float64(m.Vertices[2*k]) / 10, Y: float64(m.Vertices[2*k+1]) / 10}
		}
		for t := 0; t+2 < len(m.Indices); t += 3 {
			tr := waterTri{a: v(m.Indices[t]), b: v(m.Indices[t+1]), c: v(m.Indices[t+2]), piece: i}
			wi.tris = append(wi.tris, tr)
			n := len(wi.tris) - 1
			cellsOf(math.Min(tr.a.X, math.Min(tr.b.X, tr.c.X)), math.Min(tr.a.Y, math.Min(tr.b.Y, tr.c.Y)),
				math.Max(tr.a.X, math.Max(tr.b.X, tr.c.X)), math.Max(tr.a.Y, math.Max(tr.b.Y, tr.c.Y)),
				func(c [2]int) { wi.grid[c] = append(wi.grid[c], n) })
		}
	}
	return wi
}

// level is the lowest level of the water triangles that contain p (edges included).
func (wi *waterIndex) level(p geo.Pt) (float64, bool) {
	best, found := math.Inf(1), false
	for _, k := range wi.grid[cellOf(p)] {
		t := wi.tris[k]
		d1 := t.b.Sub(t.a).Cross(p.Sub(t.a))
		d2 := t.c.Sub(t.b).Cross(p.Sub(t.b))
		d3 := t.a.Sub(t.c).Cross(p.Sub(t.c))
		const eps = 1e-6
		neg := d1 < -eps || d2 < -eps || d3 < -eps
		pos := d1 > eps || d2 > eps || d3 > eps
		if neg && pos {
			continue
		}
		if l := wi.lvl[t.piece]; l < best {
			best, found = l, true
		}
	}
	if !found {
		return 0, false
	}
	return best, true
}
