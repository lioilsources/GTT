// Package citygml streams buildings out of a CityGML 2.0 file (IPR Praha 3D model, MLIT PLATEAU,
// specs/models.md).
//
// Only boundary surfaces are read (RoofSurface, WallSurface, GroundSurface under a Building, its
// BuildingParts and BuildingInstallations, at any LOD); solids reference the same polygons by
// xlink and are skipped. A building may carry the same shell at several LODs (PLATEAU: LOD2 for
// all, LOD3 for a few): ReadLOD keeps one of them (specs/models.md v5).
package citygml

import (
	"bufio"
	"encoding/xml"
	"fmt"
	"io"
	"strconv"
	"strings"
	"unicode/utf8"
)

type V3 struct{ X, Y, Z float64 }

type Kind byte

const (
	Wall Kind = iota
	Roof
	Ground
)

// Poly is one planar polygon: exterior ring first, then holes; rings are open (no repeated end).
type Poly struct {
	Kind  Kind
	Group int // index into Building.Groups: the innermost Building, BuildingPart or BuildingInstallation
	LOD   int // of the enclosing lodNMultiSurface (0 = none seen)
	Rings [][]V3
}

// Group is a Building, BuildingPart or BuildingInstallation inside one top-level building.
type Group struct {
	ID           string // gml:id ("" for installations without one)
	Usage        string // bldg:usage
	Installation bool
}

type Building struct {
	ID     string
	Groups []Group
	Polys  []Poly
}

// Envelope reads gml:boundedBy of the CityModel (lower and upper corner, x, y only).
func Envelope(r io.Reader) (minX, minY, maxX, maxY float64, err error) {
	d := newDecoder(r)
	var lower, upper []float64
	var cur *[]float64
	for {
		tok, err := d.Token()
		if err != nil {
			return 0, 0, 0, 0, fmt.Errorf("citygml envelope: %w", err)
		}
		switch t := tok.(type) {
		case xml.StartElement:
			switch t.Name.Local {
			case "lowerCorner":
				cur = &lower
			case "upperCorner":
				cur = &upper
			case "cityObjectMember":
				return 0, 0, 0, 0, fmt.Errorf("citygml: no envelope before the first object")
			}
		case xml.CharData:
			if cur != nil {
				*cur = floats(string(t))
				cur = nil
				if len(lower) >= 2 && len(upper) >= 2 {
					return lower[0], lower[1], upper[0], upper[1], nil
				}
			}
		}
	}
}

// Read calls fn for every top-level building. tf maps source coordinates (x, y, z) to the
// output; keep sees the building's source bounding box first and may skip it cheaply.
// Every LOD is kept (ReadLOD with lod 0 picks the highest one per building).
func Read(r io.Reader, tf func(V3) V3, keep func(minX, minY, maxX, maxY float64) bool, fn func(*Building) error) error {
	return ReadLOD(r, -1, tf, keep, fn)
}

// ReadLOD is Read keeping one LOD per building: lod if the building has polygons at it, else its
// highest. lod 0 = always the highest, lod < 0 = all of them.
func ReadLOD(r io.Reader, lod int, tf func(V3) V3, keep func(minX, minY, maxX, maxY float64) bool, fn func(*Building) error) error {
	d := newDecoder(r)
	var lodStack []int
	var (
		b       *Building
		stack   []string
		groups  []int // open group indices
		kind    = -1
		poly    *Poly
		ring    []V3
		inPos   bool
		posText strings.Builder
		usageOn bool
		usage   strings.Builder
	)
	for {
		tok, err := d.Token()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return fmt.Errorf("citygml: %w", err)
		}
		switch t := tok.(type) {
		case xml.StartElement:
			n := t.Name.Local
			stack = append(stack, n)
			if l, ok := lodOf(n); ok {
				lodStack = append(lodStack, l)
			}
			switch n {
			case "Building":
				if b == nil {
					b = &Building{ID: attr(t, "id")}
				}
				fallthrough
			case "BuildingPart", "BuildingInstallation":
				if b != nil {
					b.Groups = append(b.Groups, Group{ID: attr(t, "id"), Installation: n == "BuildingInstallation"})
					groups = append(groups, len(b.Groups)-1)
				}
			case "usage":
				usageOn = true
				usage.Reset()
			case "RoofSurface", "OuterCeilingSurface":
				// v5: PLATEAU files the underside of eaves and gate roofs as OuterCeilingSurface;
				// it is drawn like a roof (it faces down, so it never joins the roof plan).
				kind = int(Roof)
			case "WallSurface":
				kind = int(Wall)
			case "GroundSurface":
				kind = int(Ground)
			case "Polygon":
				if b != nil && kind >= 0 && len(groups) > 0 {
					poly = &Poly{Kind: Kind(kind), Group: groups[len(groups)-1]}
					if len(lodStack) > 0 {
						poly.LOD = lodStack[len(lodStack)-1]
					}
				}
			case "posList", "pos":
				if poly != nil {
					inPos = true
					posText.Reset()
				}
			}
		case xml.CharData:
			if inPos {
				posText.Write(t)
			} else if usageOn {
				usage.Write(t)
			}
		case xml.EndElement:
			n := t.Name.Local
			if len(stack) > 0 {
				stack = stack[:len(stack)-1]
			}
			if _, ok := lodOf(n); ok && len(lodStack) > 0 {
				lodStack = lodStack[:len(lodStack)-1]
			}
			switch n {
			case "usage":
				usageOn = false
				if b != nil && len(groups) > 0 {
					b.Groups[groups[len(groups)-1]].Usage = strings.TrimSpace(usage.String())
				}
			case "posList":
				if inPos {
					inPos = false
					v := floats(posText.String())
					ring = ring[:0]
					for i := 0; i+2 < len(v); i += 3 {
						ring = append(ring, V3{v[i], v[i+1], v[i+2]})
					}
				}
			case "pos":
				if inPos {
					inPos = false
					if v := floats(posText.String()); len(v) >= 3 {
						ring = append(ring, V3{v[0], v[1], v[2]})
					}
				}
			case "LinearRing":
				if poly != nil {
					if len(ring) > 1 && ring[0] == ring[len(ring)-1] {
						ring = ring[:len(ring)-1]
					}
					if len(ring) >= 3 {
						poly.Rings = append(poly.Rings, append([]V3(nil), ring...))
					} else if len(poly.Rings) == 0 {
						poly.Rings = append(poly.Rings, nil) // degenerate exterior: drop the polygon below
					}
					ring = ring[:0]
				}
			case "Polygon":
				if poly != nil && len(poly.Rings) > 0 && poly.Rings[0] != nil {
					b.Polys = append(b.Polys, *poly)
				}
				poly = nil
			case "RoofSurface", "OuterCeilingSurface", "WallSurface", "GroundSurface":
				kind = -1
			case "BuildingPart", "BuildingInstallation":
				if len(groups) > 0 {
					groups = groups[:len(groups)-1]
				}
			case "Building":
				if len(groups) > 0 {
					groups = groups[:len(groups)-1]
				}
				if len(groups) == 0 && b != nil {
					pickLOD(b, lod)
					if err := finish(b, tf, keep, fn); err != nil {
						return err
					}
					b = nil
				}
			}
		}
	}
}

func finish(b *Building, tf func(V3) V3, keep func(minX, minY, maxX, maxY float64) bool, fn func(*Building) error) error {
	if len(b.Polys) == 0 {
		return nil
	}
	x1, y1, x2, y2 := b.Polys[0].Rings[0][0].X, b.Polys[0].Rings[0][0].Y, b.Polys[0].Rings[0][0].X, b.Polys[0].Rings[0][0].Y
	for _, p := range b.Polys {
		for _, r := range p.Rings {
			for _, v := range r {
				x1, x2 = min(x1, v.X), max(x2, v.X)
				y1, y2 = min(y1, v.Y), max(y2, v.Y)
			}
		}
	}
	if keep != nil && !keep(x1, y1, x2, y2) {
		return nil
	}
	if tf != nil {
		for _, p := range b.Polys {
			for _, r := range p.Rings {
				for i := range r {
					r[i] = tf(r[i])
				}
			}
		}
	}
	return fn(b)
}

// lodOf reads the LOD of a geometry property element (lod2MultiSurface, lod3Solid, …).
func lodOf(local string) (int, bool) {
	if len(local) > 4 && strings.HasPrefix(local, "lod") && local[3] >= '0' && local[3] <= '4' {
		return int(local[3] - '0'), true
	}
	return 0, false
}

// pickLOD drops the polygons of the other LODs (lod < 0: keep all).
func pickLOD(b *Building, lod int) {
	if lod < 0 || len(b.Polys) == 0 {
		return
	}
	top, has := 0, false
	for _, p := range b.Polys {
		top = max(top, p.LOD)
		has = has || (lod > 0 && p.LOD == lod)
	}
	if !has {
		lod = top
	}
	out := b.Polys[:0]
	for _, p := range b.Polys {
		if p.LOD == lod {
			out = append(out, p)
		}
	}
	b.Polys = out
}

func attr(t xml.StartElement, local string) string {
	for _, a := range t.Attr {
		if a.Name.Local == local {
			return a.Value
		}
	}
	return ""
}

func floats(s string) []float64 {
	f := strings.Fields(s)
	out := make([]float64, 0, len(f))
	for _, x := range f {
		v, err := strconv.ParseFloat(x, 64)
		if err == nil {
			out = append(out, v)
		}
	}
	return out
}

func newDecoder(r io.Reader) *xml.Decoder {
	d := xml.NewDecoder(bufio.NewReaderSize(r, 1<<20))
	d.CharsetReader = func(label string, in io.Reader) (io.Reader, error) {
		switch strings.ToLower(label) {
		case "iso-8859-1", "latin1", "iso8859-1", "windows-1250", "cp1250":
			// Attribute texts are ASCII in practice; bytes ≥ 0x80 map one to one (Latin-1).
			return &latin1{r: bufio.NewReader(in)}, nil
		case "utf-8", "utf8":
			return in, nil
		}
		return nil, fmt.Errorf("citygml: unsupported charset %q", label)
	}
	return d
}

type latin1 struct {
	r   *bufio.Reader
	buf []byte
}

func (l *latin1) Read(p []byte) (int, error) {
	n := 0
	for n < len(p) {
		if len(l.buf) > 0 {
			k := copy(p[n:], l.buf)
			l.buf = l.buf[k:]
			n += k
			continue
		}
		c, err := l.r.ReadByte()
		if err != nil {
			if n > 0 {
				return n, nil
			}
			return 0, err
		}
		if c < utf8.RuneSelf {
			p[n] = c
			n++
			continue
		}
		var tmp [4]byte
		k := utf8.EncodeRune(tmp[:], rune(c))
		l.buf = append(l.buf[:0], tmp[:k]...)
	}
	return n, nil
}
