package steps

import (
	"math"
	"sort"

	"citypack/internal/geo"
)

// polyArea is the area of an outer ring minus its holes.
func polyArea(rings [][]geo.Pt) float64 {
	a := math.Abs(geo.SignedArea(rings[0]))
	for _, h := range rings[1:] {
		a -= math.Abs(geo.SignedArea(h))
	}
	return a
}

// largestPoly picks the biggest polygon of a body.
func largestPoly(polys [][][]geo.Pt) [][]geo.Pt {
	best, ba := -1, -1.0
	for i, p := range polys {
		if a := polyArea(p); a > ba {
			best, ba = i, a
		}
	}
	if best < 0 {
		return nil
	}
	return polys[best]
}

// scanInterval intersects the line through p with direction d against the polygon and returns
// the parameters (along d) of the inside interval that contains p, or the longest one.
func scanInterval(poly [][]geo.Pt, p, d geo.Pt) (float64, float64, bool) {
	var ts []float64
	n := geo.Pt{X: -d.Y, Y: d.X}
	for _, r := range poly {
		for i := range r {
			a, b := r[i], r[(i+1)%len(r)]
			sa, sb := a.Sub(p).Dot(n), b.Sub(p).Dot(n)
			if (sa > 0) == (sb > 0) || sa == sb {
				continue
			}
			t := sa / (sa - sb)
			q := a.Add(b.Sub(a).Mul(t))
			ts = append(ts, q.Sub(p).Dot(d))
		}
	}
	if len(ts) < 2 {
		return 0, 0, false
	}
	sort.Float64s(ts)
	bl, bh, found := 0.0, 0.0, false
	for i := 0; i+1 < len(ts); i += 2 {
		lo, hi := ts[i], ts[i+1]
		if lo <= 0 && hi >= 0 {
			return lo, hi, true
		}
		if !found || hi-lo > bh-bl {
			bl, bh, found = lo, hi, true
		}
	}
	return bl, bh, found
}

// interiorPoint is a point inside the polygon: the middle of the widest horizontal chord through
// its vertex centroid (or through the bbox middle).
func interiorPoint(poly [][]geo.Pt) geo.Pt {
	var c geo.Pt
	for _, q := range poly[0] {
		c = c.Add(q)
	}
	c = c.Mul(1 / float64(len(poly[0])))
	if geo.PointInRing(c, poly[0]) && !inAnyRing(c, poly[1:]) {
		return c
	}
	minX, minY, maxX, maxY := bounds(poly[0])
	best, bw := geo.Pt{X: (minX + maxX) / 2, Y: (minY + maxY) / 2}, -1.0
	for _, y := range []float64{c.Y, (minY + maxY) / 2, minY + (maxY-minY)/4, minY + 3*(maxY-minY)/4} {
		o := geo.Pt{X: minX - 1, Y: y}
		lo, hi, ok := scanInterval(poly, o, geo.Pt{X: 1})
		if ok && hi-lo > bw {
			bw = hi - lo
			best = o.Add(geo.Pt{X: (lo + hi) / 2})
		}
	}
	return best
}

// labelAxis is a straight label line for water: along the principal axis of the polygon,
// through an interior point, 80 % of the inside chord there.
func labelAxis(poly [][]geo.Pt) []geo.Pt {
	p := interiorPoint(poly)
	var mx, my float64
	ring := poly[0]
	for _, q := range ring {
		mx += q.X
		my += q.Y
	}
	mx /= float64(len(ring))
	my /= float64(len(ring))
	var sxx, syy, sxy float64
	for _, q := range ring {
		dx, dy := q.X-mx, q.Y-my
		sxx += dx * dx
		syy += dy * dy
		sxy += dx * dy
	}
	ang := 0.5 * math.Atan2(2*sxy, sxx-syy)
	d := geo.Pt{X: math.Cos(ang), Y: math.Sin(ang)}
	if d.X < 0 || (d.X == 0 && d.Y < 0) {
		d = d.Mul(-1) // read left to right
	}
	lo, hi, ok := scanInterval(poly, p, d)
	if !ok {
		return []geo.Pt{p, p}
	}
	mid := (lo + hi) / 2
	half := (hi - lo) * 0.4
	return []geo.Pt{p.Add(d.Mul(mid - half)), p.Add(d.Mul(mid + half))}
}

// areaName names where a spot is (specs/nature.md spots): the smallest named park containing it
// or within parkM, else the nearest named water within waterM.
func areaName(names []NatureName, p geo.Pt, parkM, waterM float64) (string, bool) {
	best, ba := "", math.Inf(1)
	for _, n := range names {
		if n.Water || n.AreaM >= ba {
			continue
		}
		if polysDist(n.Rings, p) <= parkM {
			best, ba = n.Name, n.AreaM
		}
	}
	if best != "" {
		return best, false
	}
	bd := math.Inf(1)
	for _, n := range names {
		if !n.Water {
			continue
		}
		if d := polysDist(n.Rings, p); d <= waterM && d < bd {
			best, bd = n.Name, d
		}
	}
	return best, best != ""
}

// polysDist is 0 inside any polygon, else the distance to the nearest boundary.
func polysDist(polys [][][]geo.Pt, p geo.Pt) float64 {
	d := math.Inf(1)
	for _, poly := range polys {
		if geo.PointInRing(p, poly[0]) && !inAnyRing(p, poly[1:]) {
			return 0
		}
		for _, r := range poly {
			for i := range r {
				q, _ := geo.ClosestOnSegment(p, r[i], r[(i+1)%len(r)])
				d = math.Min(d, q.Dist(p))
			}
		}
	}
	return d
}
