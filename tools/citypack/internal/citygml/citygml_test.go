package citygml

import (
	"strings"
	"testing"
)

const sample = `<?xml version="1.0" encoding="ISO-8859-1"?>
<CityModel xmlns="http://www.opengis.net/citygml/2.0" xmlns:gml="http://www.opengis.net/gml" xmlns:bldg="http://www.opengis.net/citygml/building/2.0">
 <gml:boundedBy><gml:Envelope srsDimension="3"><gml:lowerCorner>-10 -20 100</gml:lowerCorner><gml:upperCorner>30 40 150</gml:upperCorner></gml:Envelope></gml:boundedBy>
 <cityObjectMember>
  <bldg:Building gml:id="_1">
   <bldg:usage>sikma stresni plocha</bldg:usage>
   <bldg:boundedBy><bldg:GroundSurface><bldg:lod2MultiSurface><gml:MultiSurface><gml:surfaceMember><gml:Polygon><gml:exterior><gml:LinearRing>
    <gml:posList srsDimension="3">0 0 100 0 10 100 10 10 100 10 0 100 0 0 100</gml:posList></gml:LinearRing></gml:exterior></gml:Polygon></gml:surfaceMember></gml:MultiSurface></bldg:lod2MultiSurface></bldg:GroundSurface></bldg:boundedBy>
   <bldg:consistsOfBuildingPart><bldg:BuildingPart gml:id="_1p">
    <bldg:usage>vyznacna vez na strese</bldg:usage>
    <bldg:boundedBy><bldg:RoofSurface><bldg:lod2MultiSurface><gml:MultiSurface><gml:surfaceMember><gml:Polygon><gml:exterior><gml:LinearRing>
     <gml:posList srsDimension="3">0 0 110 10 0 110 10 10 110 0 10 110 0 0 110</gml:posList></gml:LinearRing></gml:exterior>
     <gml:interior><gml:LinearRing><gml:posList srsDimension="3">2 2 110 2 4 110 4 4 110 4 2 110 2 2 110</gml:posList></gml:LinearRing></gml:interior></gml:Polygon></gml:surfaceMember></gml:MultiSurface></bldg:lod2MultiSurface></bldg:RoofSurface></bldg:boundedBy>
   </bldg:BuildingPart></bldg:consistsOfBuildingPart>
   <bldg:lod2Solid><gml:Solid><gml:exterior><gml:CompositeSurface><gml:surfaceMember xlink:href="#x"/></gml:CompositeSurface></gml:exterior></gml:Solid></bldg:lod2Solid>
  </bldg:Building>
 </cityObjectMember>
 <cityObjectMember><bldg:Building gml:id="_far"><bldg:boundedBy><bldg:WallSurface><bldg:lod2MultiSurface><gml:MultiSurface><gml:surfaceMember><gml:Polygon><gml:exterior><gml:LinearRing>
  <gml:posList srsDimension="3">1000 0 0 1001 0 0 1001 0 5 1000 0 0</gml:posList></gml:LinearRing></gml:exterior></gml:Polygon></gml:surfaceMember></gml:MultiSurface></bldg:lod2MultiSurface></bldg:WallSurface></bldg:boundedBy></bldg:Building></cityObjectMember>
</CityModel>`

func TestEnvelope(t *testing.T) {
	x1, y1, x2, y2, err := Envelope(strings.NewReader(sample))
	if err != nil || x1 != -10 || y1 != -20 || x2 != 30 || y2 != 40 {
		t.Fatalf("envelope %v %v %v %v %v", x1, y1, x2, y2, err)
	}
}

func TestRead(t *testing.T) {
	var got []*Building
	keep := func(x1, _, _, _ float64) bool { return x1 < 500 }
	shift := func(v V3) V3 { return V3{v.X + 1, v.Y, v.Z} }
	if err := Read(strings.NewReader(sample), shift, keep, func(b *Building) error { got = append(got, b); return nil }); err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].ID != "_1" {
		t.Fatalf("buildings %+v", got)
	}
	b := got[0]
	if len(b.Groups) != 2 || b.Groups[1].ID != "_1p" || b.Groups[1].Usage != "vyznacna vez na strese" || b.Groups[0].Usage != "sikma stresni plocha" {
		t.Fatalf("groups %+v", b.Groups)
	}
	if len(b.Polys) != 2 {
		t.Fatalf("polys %d, want 2 (the solid's xlinks are skipped)", len(b.Polys))
	}
	g, r := b.Polys[0], b.Polys[1]
	if g.Kind != Ground || g.Group != 0 || len(g.Rings[0]) != 4 || g.Rings[0][0].X != 1 {
		t.Fatalf("ground %+v", g)
	}
	if r.Kind != Roof || r.Group != 1 || len(r.Rings) != 2 || len(r.Rings[1]) != 4 {
		t.Fatalf("roof %+v", r)
	}
}

// v5: PLATEAU carries LOD2 for every building and LOD3 (with openings) for a few; one is kept.
const multiLOD = `<CityModel xmlns="http://www.opengis.net/citygml/2.0" xmlns:gml="http://www.opengis.net/gml" xmlns:bldg="http://www.opengis.net/citygml/building/2.0">
 <cityObjectMember><bldg:Building gml:id="b">
  <bldg:lod0FootPrint><gml:MultiSurface><gml:surfaceMember><gml:Polygon><gml:exterior><gml:LinearRing><gml:posList>0 0 0 1 0 0 1 1 0 0 0 0</gml:posList></gml:LinearRing></gml:exterior></gml:Polygon></gml:surfaceMember></gml:MultiSurface></bldg:lod0FootPrint>
  <bldg:boundedBy><bldg:RoofSurface><bldg:lod2MultiSurface><gml:MultiSurface><gml:surfaceMember><gml:Polygon><gml:exterior><gml:LinearRing><gml:posList>0 0 5 1 0 5 1 1 5 0 0 5</gml:posList></gml:LinearRing></gml:exterior></gml:Polygon></gml:surfaceMember></gml:MultiSurface></bldg:lod2MultiSurface></bldg:RoofSurface></bldg:boundedBy>
  <bldg:boundedBy><bldg:RoofSurface><bldg:lod3MultiSurface><gml:MultiSurface><gml:surfaceMember><gml:Polygon><gml:exterior><gml:LinearRing><gml:posList>0 0 6 1 0 6 1 1 6 0 0 6</gml:posList></gml:LinearRing></gml:exterior></gml:Polygon></gml:surfaceMember></gml:MultiSurface></bldg:lod3MultiSurface></bldg:RoofSurface></bldg:boundedBy>
  <bldg:boundedBy><bldg:OuterCeilingSurface><bldg:lod2MultiSurface><gml:MultiSurface><gml:surfaceMember><gml:Polygon><gml:exterior><gml:LinearRing><gml:posList>0 0 4 0 1 4 1 1 4 0 0 4</gml:posList></gml:LinearRing></gml:exterior></gml:Polygon></gml:surfaceMember></gml:MultiSurface></bldg:lod2MultiSurface></bldg:OuterCeilingSurface></bldg:boundedBy>
  <bldg:boundedBy><bldg:WallSurface><bldg:lod3MultiSurface><gml:MultiSurface><gml:surfaceMember><gml:Polygon><gml:exterior><gml:LinearRing><gml:posList>0 0 0 1 0 0 1 0 6 0 0 0</gml:posList></gml:LinearRing></gml:exterior></gml:Polygon></gml:surfaceMember></gml:MultiSurface></bldg:lod3MultiSurface></bldg:WallSurface></bldg:boundedBy>
 </bldg:Building></cityObjectMember>
</CityModel>`

func TestReadLOD(t *testing.T) {
	for _, c := range []struct{ lod, polys, want int }{{-1, 4, -1}, {0, 2, 3}, {2, 2, 2}, {1, 2, 3}} {
		var got *Building
		if err := ReadLOD(strings.NewReader(multiLOD), c.lod, nil, nil, func(b *Building) error { got = b; return nil }); err != nil {
			t.Fatal(err)
		}
		if got == nil || len(got.Polys) != c.polys {
			t.Fatalf("lod %d: %+v", c.lod, got)
		}
		for _, p := range got.Polys {
			if p.Kind == Ground || p.Kind == Wall && p.LOD == 2 {
				t.Fatalf("lod %d: kind %v at LOD %d", c.lod, p.Kind, p.LOD) // the ceiling reads as a roof
			}
			if c.want >= 0 && p.LOD != c.want {
				t.Fatalf("lod %d: polygon at LOD %d, want %d", c.lod, p.LOD, c.want)
			}
		}
	}
}
