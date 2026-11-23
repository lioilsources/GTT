package steps

import (
	"encoding/csv"
	"fmt"
	"log/slog"
	"math"
	"os"
	"sort"
	"strconv"

	"citypack/internal/duck"
	"citypack/internal/geo"
)

// AlleyReport is alleys.json: alleys narrower than flow.gap_close_m and their bollard lines.
type AlleyReport struct {
	Micro    []int        `json:"micro"` // edge indices into graph.pb
	Barriers []BarrierRow `json:"barriers"`
}

const alleyProbeM = 10.0 // probe reach to each side; a free side counts as this

// Alleys marks alleys whose real clear width between the source building footprints is below
// flow.gap_close_m as micro_only and puts bollard lines across both ends (specs/flow.md FL0).
// The game corridor is wider than the real alley (widen), so the width is measured against the
// unclipped Overture footprints.
func Alleys(e *Env) error {
	out := e.W("alleys.json")
	if e.fresh(out) {
		skip("alleys", out)
		return nil
	}
	g, err := e.LoadGraph()
	if err != nil {
		return err
	}
	probes := e.W("alley_probes.csv")
	f, err := os.Create(probes)
	if err != nil {
		return err
	}
	w := csv.NewWriter(f)
	_ = w.Write([]string{"edge", "i", "side", "px", "py", "wkt"})
	samples := map[int]int{}
	for ei, ed := range g.Edges {
		if ed.Kept || ed.Tunnel || ed.Bridge || ed.LayerFrom != 0 || ed.LayerTo != 0 {
			continue
		}
		pts := EdgePts(ed)
		total := geo.PolylineLength(pts)
		// Skip the ends where the alley opens onto the crossing street.
		margin := math.Min(8, total/3)
		i := 0
		for s := margin; s <= total-margin+1e-9; s += 4 {
			p, dir := along(pts, s)
			n := geo.Pt{X: -dir.Y, Y: dir.X}
			for side, sg := range []float64{1, -1} {
				q := p.Add(n.Mul(sg * alleyProbeM))
				_ = w.Write([]string{strconv.Itoa(ei), strconv.Itoa(i), strconv.Itoa(side),
					fmt.Sprintf("%.2f", p.X), fmt.Sprintf("%.2f", p.Y),
					fmt.Sprintf("LINESTRING(%.2f %.2f,%.2f %.2f)", p.X, p.Y, q.X, q.Y)})
			}
			i++
		}
		samples[ei] = i
	}
	w.Flush()
	if err := f.Close(); err != nil {
		return err
	}
	area := e.projSQL("ST_GeomFromText(" + duck.Quote(e.C.City.AreaWKT()) + ")")
	rows, err := duck.Query("alleys", fmt.Sprintf(`
CREATE TABLE area AS SELECT ST_Buffer(%[1]s, 50) AS g;
CREATE TABLE b AS SELECT ST_MakeValid(%[2]s) AS g FROM read_parquet(%[3]s) WHERE NOT coalesce(is_underground, false);
DELETE FROM b WHERE NOT ST_Intersects(g, (SELECT g FROM area));
CREATE TABLE pr AS SELECT edge::INT AS edge, i::INT AS i, side::INT AS side, ST_Point(px::DOUBLE, py::DOUBLE) AS p,
  ST_GeomFromText(wkt) AS s FROM read_csv(%[4]s, header=true, all_varchar=true);`,
		area, e.projSQL("geometry"), duck.Quote(e.Raw("building")), duck.Quote(probes)),
		`SELECT pr.edge, pr.i, pr.side, min(ST_Distance(pr.p, ST_Intersection(pr.s, b.g))) AS d
  FROM pr JOIN b ON ST_Intersects(pr.s, b.g) GROUP BY ALL ORDER BY ALL`)
	if err != nil {
		return err
	}
	type key struct{ e, i int }
	width := map[key]float64{}
	hits := map[key]int{}
	for _, r := range rows {
		ei, _ := strconv.Atoi(r[0])
		i, _ := strconv.Atoi(r[1])
		d, _ := strconv.ParseFloat(r[3], 64)
		width[key{ei, i}] += d
		hits[key{ei, i}]++
	}
	gap := e.C.Tuning.Flow.GapCloseM
	rep := AlleyReport{}
	var edges []int
	for ei := range samples {
		edges = append(edges, ei)
	}
	sort.Ints(edges)
	for _, ei := range edges {
		n := samples[ei]
		if n == 0 {
			continue
		}
		ws := make([]float64, 0, n)
		for i := 0; i < n; i++ {
			k := key{ei, i}
			ws = append(ws, width[k]+float64(2-hits[k])*alleyProbeM)
		}
		sort.Float64s(ws)
		if ws[len(ws)/2] < gap {
			rep.Micro = append(rep.Micro, ei)
		}
	}
	// Bollards: a line across the alley at each end, just outside the crossing street's corridor.
	nodeHW := make([]float64, len(g.Nodes))
	for _, ed := range g.Edges {
		for _, n := range []uint32{ed.From, ed.To} {
			nodeHW[n] = math.Max(nodeHW[n], float64(ed.WidthM)/2)
		}
	}
	// Ground road segments, to keep bollard lines off every other road's centre line.
	type seg struct {
		a, b geo.Pt
		edge int
	}
	segGrid := map[[2]int][]seg{}
	for ei, ed := range g.Edges {
		if ed.Tunnel || ed.LayerFrom != 0 || ed.LayerTo != 0 {
			continue
		}
		pts := EdgePts(ed)
		for k := 1; k < len(pts); k++ {
			s := seg{pts[k-1], pts[k], ei}
			cellsOf(math.Min(s.a.X, s.b.X), math.Min(s.a.Y, s.b.Y), math.Max(s.a.X, s.b.X), math.Max(s.a.Y, s.b.Y),
				func(c [2]int) { segGrid[c] = append(segGrid[c], s) })
		}
	}
	crosses := func(a, b geo.Pt, self int) bool {
		hit := false
		cellsOf(math.Min(a.X, b.X), math.Min(a.Y, b.Y), math.Max(a.X, b.X), math.Max(a.Y, b.Y), func(c [2]int) {
			for _, s := range segGrid[c] {
				if s.edge == self || hit {
					continue
				}
				if _, ok := geo.SegmentIntersect(a, b, s.a, s.b); ok {
					hit = true
				}
			}
		})
		return hit
	}
	cm := float64(e.C.Tuning.ChunkM)
	for _, ei := range rep.Micro {
		ed := g.Edges[ei]
		pts := EdgePts(ed)
		total := geo.PolylineLength(pts)
		hw := float64(ed.WidthM)/2 + 1
		// One line near each end, walked inward (2 m steps, at most to the middle) until it
		// clears every other road; a short alley gets a single line in the middle.
		place := func(s0, step, limit float64) {
			for s := s0; (step > 0 && s <= limit) || (step < 0 && s >= limit) || step == 0; s += step {
				p, dir := along(pts, s)
				n := geo.Pt{X: -dir.Y, Y: dir.X}
				a, b := p.Add(n.Mul(hw)), p.Sub(n.Mul(hw))
				if !crosses(a, b, ei) {
					rep.Barriers = append(rep.Barriers, BarrierRow{CX: int(math.Floor(p.X / cm)), CY: int(math.Floor(p.Y / cm)), Pts: []geo.Pt{a, b}})
					return
				}
				if step == 0 {
					return
				}
			}
		}
		from, to := nodeHW[ed.From]+2, total-nodeHW[ed.To]-2
		if from >= to {
			place(total/2, 0, 0)
			continue
		}
		place(from, 2, total/2)
		place(to, -2, total/2)
	}
	slog.Info("alleys", "alleys", len(samples), "micro_only", len(rep.Micro), "bollard_lines", len(rep.Barriers))
	return writeJSON(out, rep)
}

// along returns the point at arc length s on a polyline and the unit direction there.
func along(pts []geo.Pt, s float64) (geo.Pt, geo.Pt) {
	for k := 1; k < len(pts); k++ {
		l := pts[k].Dist(pts[k-1])
		if l == 0 {
			continue
		}
		dir := pts[k].Sub(pts[k-1]).Mul(1 / l)
		if s <= l || k == len(pts)-1 {
			return pts[k-1].Add(dir.Mul(math.Min(s, l))), dir
		}
		s -= l
	}
	return pts[0], geo.Pt{X: 1}
}

// LoadAlleys reads alleys.json (empty when the step has not run).
func (e *Env) LoadAlleys() (AlleyReport, error) {
	var r AlleyReport
	if _, err := os.Stat(e.W("alleys.json")); os.IsNotExist(err) {
		return r, nil
	}
	return r, readJSON(e.W("alleys.json"), &r)
}
