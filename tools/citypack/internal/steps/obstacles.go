package steps

import (
	"math"

	"citypack/internal/geo"
	"citypack/internal/pb"
)

const obstacleCell = 16.0

// obstacleReach is the farthest any query looks past a feature (crown radius, sidewalk snap).
const obstacleReach = 24.0

type roadSeg struct {
	a, b     geo.Pt
	hw, hc   float64 // corridor and carriageway half widths
	sidewalk float64 // 0 for alleys
	street   bool    // kept road or residential alley: street trees line it
}

type polyRef struct {
	rings [][]geo.Pt
}

type edgeSeg struct{ a, b geo.Pt }

// obstacles indexes ground roads, colliding buildings and water for tree placement and checks.
type obstacles struct {
	roads     []roadSeg
	roadGrid  map[[2]int][]int
	polys     []polyRef
	polyKind  []int // 0 building, 1 water
	polyGrid  map[[2]int][]int
	edges     []edgeSeg
	edgeKind  []int
	edgeGrid  map[[2]int][]int
	sidewalkM float64
}

func cellsOf(minX, minY, maxX, maxY float64, f func(k [2]int)) {
	for x := int(math.Floor(minX / obstacleCell)); x <= int(math.Floor(maxX/obstacleCell)); x++ {
		for y := int(math.Floor(minY / obstacleCell)); y <= int(math.Floor(maxY/obstacleCell)); y++ {
			f([2]int{x, y})
		}
	}
}

func cellOf(p geo.Pt) [2]int {
	return [2]int{int(math.Floor(p.X / obstacleCell)), int(math.Floor(p.Y / obstacleCell))}
}

func newObstacles(e *Env, g *pb.Graph, masses []MassRow, water []NaturePiece) *obstacles {
	ob := &obstacles{roadGrid: map[[2]int][]int{}, polyGrid: map[[2]int][]int{}, edgeGrid: map[[2]int][]int{}, sidewalkM: e.C.Tuning.SidewalkWidthM}
	for _, ed := range g.Edges {
		if !groundEdge(ed) { // a sunken road that is not a tunnel lies on the terrain too
			continue
		}
		hw := float64(ed.WidthM) / 2
		hc, sw := hw, 0.0
		if ed.Kept {
			sw = e.C.Tuning.SidewalkWidthM
			hc = hw - sw
		}
		pts := EdgePts(ed)
		for k := 1; k < len(pts); k++ {
			s := roadSeg{a: pts[k-1], b: pts[k], hw: hw, hc: hc, sidewalk: sw, street: ed.Kept || ed.Class == pb.RoadClass_RESIDENTIAL}
			ob.roads = append(ob.roads, s)
			r := hw + obstacleReach
			cellsOf(math.Min(s.a.X, s.b.X)-r, math.Min(s.a.Y, s.b.Y)-r, math.Max(s.a.X, s.b.X)+r, math.Max(s.a.Y, s.b.Y)+r,
				func(c [2]int) { ob.roadGrid[c] = append(ob.roadGrid[c], len(ob.roads)-1) })
		}
	}
	addPoly := func(rings [][]geo.Pt, kind int) {
		ob.polys = append(ob.polys, polyRef{rings})
		ob.polyKind = append(ob.polyKind, kind)
		pi := len(ob.polys) - 1
		minX, minY, maxX, maxY := bounds(rings[0])
		cellsOf(minX, minY, maxX, maxY, func(c [2]int) { ob.polyGrid[c] = append(ob.polyGrid[c], pi) })
		for _, r := range rings {
			for i := range r {
				s := edgeSeg{r[i], r[(i+1)%len(r)]}
				ob.edges = append(ob.edges, s)
				ob.edgeKind = append(ob.edgeKind, kind)
				ei := len(ob.edges) - 1
				cellsOf(math.Min(s.a.X, s.b.X)-obstacleReach, math.Min(s.a.Y, s.b.Y)-obstacleReach,
					math.Max(s.a.X, s.b.X)+obstacleReach, math.Max(s.a.Y, s.b.Y)+obstacleReach,
					func(c [2]int) { ob.edgeGrid[c] = append(ob.edgeGrid[c], ei) })
			}
		}
	}
	for _, m := range masses {
		if m.MinH < 0.5 {
			addPoly(m.Rings, 0)
		}
	}
	for _, w := range water {
		addPoly(w.Rings, 1)
	}
	return ob
}

func (ob *obstacles) inside(p geo.Pt, kind int) bool {
	for _, pi := range ob.polyGrid[cellOf(p)] {
		if ob.polyKind[pi] != kind {
			continue
		}
		r := ob.polys[pi].rings
		if geo.PointInRing(p, r[0]) && !inAnyRing(p, r[1:]) {
			return true
		}
	}
	return false
}

func (ob *obstacles) nearEdge(p geo.Pt, r float64, kind int) bool {
	for _, ei := range ob.edgeGrid[cellOf(p)] {
		if ob.edgeKind[ei] != kind {
			continue
		}
		q, _ := geo.ClosestOnSegment(p, ob.edges[ei].a, ob.edges[ei].b)
		if q.Dist(p) < r {
			return true
		}
	}
	return false
}

func (ob *obstacles) inBuilding(p geo.Pt, r float64) bool {
	return ob.inside(p, 0) || ob.nearEdge(p, r, 0)
}

func (ob *obstacles) inWater(p geo.Pt, r float64) bool {
	return ob.inside(p, 1) || ob.nearEdge(p, r, 1)
}

// nearRoad: within r of any ground road corridor (sidewalks included).
func (ob *obstacles) nearRoad(p geo.Pt, r float64) bool {
	for _, si := range ob.roadGrid[cellOf(p)] {
		s := ob.roads[si]
		q, _ := geo.ClosestOnSegment(p, s.a, s.b)
		if q.Dist(p) < s.hw+r {
			return true
		}
	}
	return false
}

// onCarriageway: within m of any driven surface (corridor minus sidewalks).
func (ob *obstacles) onCarriageway(p geo.Pt, m float64) bool {
	for _, si := range ob.roadGrid[cellOf(p)] {
		s := ob.roads[si]
		q, _ := geo.ClosestOnSegment(p, s.a, s.b)
		if q.Dist(p) < s.hc+m {
			return true
		}
	}
	return false
}

// sidewalk snaps p to the sidewalk of the nearest street whose centre line is within snap
// metres, on the same side: the middle of the game sidewalk of a kept road, or just outside the
// corridor of a residential alley (the game alley is narrower than the real street, the real
// sidewalk stays between its corridor and the buildings).
func (ob *obstacles) sidewalk(p geo.Pt, snap float64) (geo.Pt, bool) {
	best, bd := -1, math.Inf(1)
	var bq geo.Pt
	for _, si := range ob.roadGrid[cellOf(p)] {
		s := ob.roads[si]
		if !s.street {
			continue
		}
		q, _ := geo.ClosestOnSegment(p, s.a, s.b)
		if d := q.Dist(p); d < bd {
			best, bd, bq = si, d, q
		}
	}
	if best < 0 || bd > snap {
		return geo.Pt{}, false
	}
	s := ob.roads[best]
	dir := s.b.Sub(s.a)
	l := dir.Len()
	if l == 0 {
		return geo.Pt{}, false
	}
	n := geo.Pt{X: -dir.Y / l, Y: dir.X / l}
	if p.Sub(bq).Dot(n) < 0 {
		n = n.Mul(-1)
	}
	off := s.hc + s.sidewalk/2
	if s.sidewalk == 0 {
		off = s.hw + alleyTreeM
	}
	return bq.Add(n.Mul(off)), true
}

// alleyTreeM: street trees of a residential alley stand this far outside its corridor (more
// than the trunk radius plus streetTrunkMargin, so they pass the carriageway check).
const alleyTreeM = 1.5

// streetTrunkMargin: a street tree's trunk centre stays this much farther than the trunk radius
// from any carriageway.
const streetTrunkMargin = 0.5

// pointGrid is a bucket grid of placed points.
type pointGrid struct {
	cell float64
	m    map[[2]int][]geo.Pt
}

func newPointGrid(cell float64) *pointGrid { return &pointGrid{cell: cell, m: map[[2]int][]geo.Pt{}} }

func (g *pointGrid) key(p geo.Pt) [2]int {
	return [2]int{int(math.Floor(p.X / g.cell)), int(math.Floor(p.Y / g.cell))}
}

func (g *pointGrid) add(p geo.Pt) { k := g.key(p); g.m[k] = append(g.m[k], p) }

func (g *pointGrid) near(p geo.Pt, d float64) bool {
	k := g.key(p)
	r := int(math.Ceil(d / g.cell))
	for x := k[0] - r; x <= k[0]+r; x++ {
		for y := k[1] - r; y <= k[1]+r; y++ {
			for _, q := range g.m[[2]int{x, y}] {
				if q.Dist(p) < d {
					return true
				}
			}
		}
	}
	return false
}

func (g *pointGrid) within(minX, minY, maxX, maxY float64) []geo.Pt {
	var out []geo.Pt
	for x := int(math.Floor(minX / g.cell)); x <= int(math.Floor(maxX/g.cell)); x++ {
		for y := int(math.Floor(minY / g.cell)); y <= int(math.Floor(maxY/g.cell)); y++ {
			out = append(out, g.m[[2]int{x, y}]...)
		}
	}
	return out
}
