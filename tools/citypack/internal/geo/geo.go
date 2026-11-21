// Package geo holds the local projection and small planar helpers.
package geo

import (
	"math"

	earcut "github.com/rclancey/go-earcut"
)

const EarthR = 6371008.8

type Pt struct{ X, Y float64 }

func (a Pt) Sub(b Pt) Pt        { return Pt{a.X - b.X, a.Y - b.Y} }
func (a Pt) Add(b Pt) Pt        { return Pt{a.X + b.X, a.Y + b.Y} }
func (a Pt) Mul(k float64) Pt   { return Pt{a.X * k, a.Y * k} }
func (a Pt) Dot(b Pt) float64   { return a.X*b.X + a.Y*b.Y }
func (a Pt) Cross(b Pt) float64 { return a.X*b.Y - a.Y*b.X }
func (a Pt) Len() float64       { return math.Hypot(a.X, a.Y) }
func (a Pt) Dist(b Pt) float64  { return a.Sub(b).Len() }

// Projection is the local equirectangular projection around an origin.
type Projection struct {
	Lat0, Lon0 float64
	cos0       float64
}

func NewProjection(lat0, lon0 float64) Projection {
	return Projection{Lat0: lat0, Lon0: lon0, cos0: math.Cos(lat0 * math.Pi / 180)}
}

func (p Projection) Forward(lon, lat float64) Pt {
	return Pt{
		X: (lon - p.Lon0) * math.Pi / 180 * p.cos0 * EarthR,
		Y: (lat - p.Lat0) * math.Pi / 180 * EarthR,
	}
}

func (p Projection) Inverse(q Pt) (lon, lat float64) {
	lon = p.Lon0 + q.X/(p.cos0*EarthR)*180/math.Pi
	lat = p.Lat0 + q.Y/EarthR*180/math.Pi
	return
}

// DM converts metres to integer decimetres.
func DM(m float64) int32 { return int32(math.Round(m * 10)) }

// PointInRing is an even-odd test.
func PointInRing(p Pt, ring []Pt) bool {
	in := false
	for i, j := 0, len(ring)-1; i < len(ring); j, i = i, i+1 {
		a, b := ring[i], ring[j]
		if (a.Y > p.Y) != (b.Y > p.Y) && p.X < (b.X-a.X)*(p.Y-a.Y)/(b.Y-a.Y)+a.X {
			in = !in
		}
	}
	return in
}

// SignedArea is positive for counter-clockwise rings.
func SignedArea(ring []Pt) float64 {
	s := 0.0
	for i, j := 0, len(ring)-1; i < len(ring); j, i = i, i+1 {
		s += ring[j].Cross(ring[i])
	}
	return s / 2
}

// SegmentIntersect returns the parameter t along a→b where it crosses c→d.
func SegmentIntersect(a, b, c, d Pt) (float64, bool) {
	r, s := b.Sub(a), d.Sub(c)
	den := r.Cross(s)
	if math.Abs(den) < 1e-12 {
		return 0, false
	}
	t := c.Sub(a).Cross(s) / den
	u := c.Sub(a).Cross(r) / den
	if t < 0 || t > 1 || u < 0 || u > 1 {
		return 0, false
	}
	return t, true
}

// ClosestOnSegment returns the closest point on a→b to p and its parameter.
func ClosestOnSegment(p, a, b Pt) (Pt, float64) {
	ab := b.Sub(a)
	l2 := ab.Dot(ab)
	if l2 == 0 {
		return a, 0
	}
	t := math.Max(0, math.Min(1, p.Sub(a).Dot(ab)/l2))
	return a.Add(ab.Mul(t)), t
}

// PolylineLength sums segment lengths.
func PolylineLength(pts []Pt) float64 {
	s := 0.0
	for i := 1; i < len(pts); i++ {
		s += pts[i].Dist(pts[i-1])
	}
	return s
}

// Triangulate runs earcut on an outer ring plus holes (rings without closing duplicate).
// It returns indices into the concatenation of all rings.
func Triangulate(rings [][]Pt) ([]int, error) {
	var data []float64
	var holes []int
	n := 0
	for i, r := range rings {
		if i > 0 {
			holes = append(holes, n)
		}
		for _, p := range r {
			data = append(data, p.X, p.Y)
		}
		n += len(r)
	}
	return earcut.Earcut(data, holes, 2)
}

// OpenRing drops the closing duplicate vertex and consecutive duplicates.
func OpenRing(r []Pt) []Pt {
	out := make([]Pt, 0, len(r))
	for _, p := range r {
		if len(out) > 0 && out[len(out)-1].Dist(p) < 0.05 {
			continue
		}
		out = append(out, p)
	}
	if len(out) > 1 && out[0].Dist(out[len(out)-1]) < 0.05 {
		out = out[:len(out)-1]
	}
	return out
}

// Orient makes the ring counter-clockwise when ccw is true, clockwise otherwise.
func Orient(r []Pt, ccw bool) []Pt {
	if (SignedArea(r) > 0) != ccw {
		out := make([]Pt, len(r))
		for i := range r {
			out[i] = r[len(r)-1-i]
		}
		return out
	}
	return r
}

// Canonical rotates a ring to start at its lowest (x, then y) vertex after rounding to
// decimetres, so the same polygon always serialises the same way.
func Canonical(r []Pt) []Pt {
	if len(r) == 0 {
		return r
	}
	k := 0
	for i, p := range r {
		a, b := DM(p.X), DM(r[k].X)
		if a < b || (a == b && DM(p.Y) < DM(r[k].Y)) {
			k = i
		}
	}
	out := make([]Pt, 0, len(r))
	out = append(out, r[k:]...)
	return append(out, r[:k]...)
}
