package steps

import (
	"encoding/binary"
	"math"
	"os"
	"sort"

	"citypack/internal/geo"
	"citypack/internal/pb"

	"google.golang.org/protobuf/proto"
)

// NatureVersion is Manifest.nature_version written by packs with classified water, green and
// trees (specs/nature.md v1).
const NatureVersion = 1

// LoadPackGraph is the graph the pack ships: graph_z.pb (heights, densified edges) when the
// elevation step ran for a city with elevation sources, else graph.pb.
func (e *Env) LoadPackGraph() (*pb.Graph, error) {
	if len(e.C.City.ElevationSources) > 0 {
		if b, err := os.ReadFile(e.W("graph_z.pb")); err == nil {
			g := &pb.Graph{}
			return g, proto.Unmarshal(b, g)
		}
	}
	return e.LoadGraph()
}

// baseZ is the lowest terrain under a footprint (vertices and their centroid), dm.
func baseZ(tg *TerrainGrid, ring []geo.Pt) int32 {
	lo := tg.At(centroid(ring))
	for _, p := range ring {
		lo = math.Min(lo, tg.At(p))
	}
	return geo.DM(lo)
}

// chunkTerrain slices the 33 × 33 terrain and shade of chunk (cx, cy).
func chunkTerrain(tg *TerrainGrid, cx, cy int) ([]byte, []byte) {
	per := int(math.Round(tg.ChunkM / tg.Step))
	n := per + 1
	z := make([]byte, 2*n*n)
	sh := make([]byte, n*n)
	i0, j0 := (cx-tg.CX0)*per, (cy-tg.CY0)*per
	for j := 0; j < n; j++ {
		for i := 0; i < n; i++ {
			gi := max(0, min(tg.W-1, i0+i))
			gj := max(0, min(tg.H-1, j0+j))
			k := gj*tg.W + gi
			binary.LittleEndian.PutUint16(z[2*(j*n+i):], uint16(tg.Z[k]))
			sh[j*n+i] = tg.Shade[k]
		}
	}
	return z, sh
}

// packNature is the nature content for the chunks.
type packNature struct {
	water, shore, green []NaturePiece
	waterZ              []int32 // per water piece, game dm
	labels              []labelRow
	trees               []Tree
	chunkM              float64
}

type labelRow struct {
	cx, cy int
	l      *pb.Label
}

// loadNatureForPack reads the nature step outputs (nil when the step has not run).
func (e *Env) loadNatureForPack(elev *ElevationReport) (*packNature, error) {
	if _, err := os.Stat(e.W("nature_names.jsonl")); os.IsNotExist(err) {
		return nil, nil
	}
	n := &packNature{chunkM: float64(e.C.Tuning.ChunkM)}
	var err error
	if n.water, err = e.LoadNaturePieces("nature_water.jsonl"); err != nil {
		return nil, err
	}
	if n.shore, err = e.LoadNaturePieces("nature_shore.jsonl"); err != nil {
		return nil, err
	}
	if n.green, err = e.LoadNaturePieces("nature_green.jsonl"); err != nil {
		return nil, err
	}
	for i, w := range n.water {
		z := 0.0
		if elev != nil {
			z = elev.WaterLevels[waterKey(w, i)]
		}
		n.waterZ = append(n.waterZ, geo.DM(z))
	}
	names, err := e.LoadNatureNames()
	if err != nil {
		return nil, err
	}
	np := e.C.Tuning.Nature.Pipeline
	for _, b := range names {
		minHa := np.LabelGreenHa
		if b.Water {
			minHa = np.LabelWaterHa
		}
		if b.AreaM < minHa*1e4 || len(b.Rings) == 0 {
			continue
		}
		poly := largestPoly(b.Rings)
		var axis []geo.Pt
		if b.Water {
			axis = labelAxis(poly)
		} else {
			axis = []geo.Pt{interiorPoint(poly)}
		}
		l := &pb.Label{Name: b.Name, Water: b.Water, AreaM2: uint32(math.Round(b.AreaM))}
		for _, p := range axis {
			l.Axis = append(l.Axis, geo.DM(p.X), geo.DM(p.Y))
		}
		mid := axis[0].Add(axis[len(axis)-1]).Mul(0.5)
		n.labels = append(n.labels, labelRow{int(math.Floor(mid.X / n.chunkM)), int(math.Floor(mid.Y / n.chunkM)), l})
	}
	if _, err := os.Stat(e.W("nature_trees.json")); err == nil {
		tr, err := e.LoadTrees()
		if err != nil {
			return nil, err
		}
		n.trees = tr.Trees
	}
	return n, nil
}

func naturePieceMesh(p NaturePiece, kind pb.GroundKind) (*pb.Mesh, bool) {
	idx, err := geo.Triangulate(p.Rings)
	if err != nil || len(idx) == 0 {
		return nil, false
	}
	m := &pb.Mesh{Kind: kind, Name: p.Name}
	for _, r := range p.Rings {
		for _, q := range r {
			m.Vertices = append(m.Vertices, geo.DM(q.X), geo.DM(q.Y))
		}
	}
	for _, i := range idx {
		m.Indices = append(m.Indices, uint32(i))
	}
	return m, true
}

// addTo puts water, shore, green, labels and trees into their chunks; it returns the number of
// polygons that failed to triangulate.
func (n *packNature) addTo(chunk func(x, y int) *pb.Chunk) int {
	failed := 0
	order := func(ps []NaturePiece) []int {
		ix := make([]int, len(ps))
		for i := range ix {
			ix[i] = i
		}
		sort.SliceStable(ix, func(a, b int) bool {
			pa, pb := ps[ix[a]], ps[ix[b]]
			if pa.CX != pb.CX {
				return pa.CX < pb.CX
			}
			if pa.CY != pb.CY {
				return pa.CY < pb.CY
			}
			if pa.Class != pb.Class {
				return pa.Class < pb.Class
			}
			return ringsLess(pa.Rings, pb.Rings)
		})
		return ix
	}
	for _, i := range order(n.water) {
		w := n.water[i]
		m, ok := naturePieceMesh(w, pb.GroundKind_WATER)
		if !ok {
			failed++
			continue
		}
		m.WaterClass = pb.WaterClass(w.Class)
		m.ZDm = n.waterZ[i]
		c := chunk(w.CX, w.CY)
		c.Ground = append(c.Ground, m)
	}
	for _, i := range order(n.green) {
		gp := n.green[i]
		m, ok := naturePieceMesh(gp, pb.GroundKind_PARK)
		if !ok {
			failed++
			continue
		}
		m.GreenClass = pb.GreenClass(gp.Class)
		m.Surface = greenSurface(m.GreenClass)
		c := chunk(gp.CX, gp.CY)
		c.Ground = append(c.Ground, m)
	}
	for _, i := range order(n.shore) {
		s := n.shore[i]
		m, ok := naturePieceMesh(s, pb.GroundKind_WATER)
		if !ok {
			failed++
			continue
		}
		c := chunk(s.CX, s.CY)
		c.Shore = append(c.Shore, m)
	}
	sort.SliceStable(n.labels, func(a, b int) bool { return n.labels[a].l.Name < n.labels[b].l.Name })
	for _, l := range n.labels {
		c := chunk(l.cx, l.cy)
		c.Labels = append(c.Labels, l.l)
	}
	for _, t := range n.trees {
		cx, cy := int(math.Floor(t.X/n.chunkM)), int(math.Floor(t.Y/n.chunkM))
		x := math.Max(0, math.Min(255, math.Round(t.X-float64(cx)*n.chunkM)))
		y := math.Max(0, math.Min(255, math.Round(t.Y-float64(cy)*n.chunkM)))
		c := chunk(cx, cy)
		c.Trees = append(c.Trees, byte(x), byte(y), byte(t.Size&3|t.Jitter<<2))
	}
	return failed
}
