package steps

import (
	"fmt"
	"log/slog"
	"math"
	"os"
	"sort"

	"citypack/internal/geo"
)

// T3 checks (specs/terrain.md, conform): water stays flat under bridges, and the car, which
// rides the terrain on ground roads, reads the road profile there.

// conformSeg mirrors terrain.Road for validate: the roads conform lets carry grid nodes.
type conformSeg struct {
	a, b   geo.Pt
	za, zb float64
	strip  float64
	hw     float64
	kept   bool
	edge   int
}

type conformIndex struct {
	segs    []conformSeg
	grid    map[[2]int][]int
	support float64
	margin  float64
}

// newConformIndex: the ground edges, as conform receives them (elevation.go).
func newConformIndex(p *PackData, sidewalkM, support, margin float64) *conformIndex {
	ci := &conformIndex{grid: map[[2]int][]int{}, support: support, margin: margin}
	for i, ed := range p.Graph.Edges {
		if !groundEdge(ed) {
			continue
		}
		pts, zs := EdgePts(ed), edgeZ(ed)
		if len(zs) != len(pts) {
			continue
		}
		strip := carriageway(ed, sidewalkM)
		for k := 1; k < len(pts); k++ {
			s := conformSeg{a: pts[k-1], b: pts[k], za: zs[k-1], zb: zs[k], strip: strip, hw: float64(ed.WidthM) / 2, kept: ed.Kept, edge: i}
			ci.segs = append(ci.segs, s)
			n := len(ci.segs) - 1
			r := math.Max(strip, float64(ed.WidthM)/2+margin) + support
			cellsOf(math.Min(s.a.X, s.b.X)-r, math.Min(s.a.Y, s.b.Y)-r, math.Max(s.a.X, s.b.X)+r, math.Max(s.a.Y, s.b.Y)+r,
				func(c [2]int) { ci.grid[c] = append(ci.grid[c], n) })
		}
	}
	return ci
}

// assign returns the road whose height conform puts on grid node c (rank: kept strip, other
// strip; then nearest strip; then higher), only among roads whose strip needs c (only >= 0:
// among that edge's segments). ok is false when no strip needs c.
func (ci *conformIndex) assign(c geo.Pt, inWater bool, only int) (edge int, z float64, ok bool) {
	bestRank, bestD, bestZ := 3, math.Inf(1), 0.0
	edge = -1
	for _, k := range ci.grid[cellOf(c)] {
		s := ci.segs[k]
		if only >= 0 && s.edge != only {
			continue
		}
		q, t := geo.ClosestOnSegment(c, s.a, s.b)
		dist := q.Dist(c)
		d := dist - s.strip
		// pack points and heights are rounded to dm
		if d > ci.support+0.15 && dist-s.hw-ci.margin > ci.support+0.15 {
			continue
		}
		rank := 1
		if s.kept && d <= ci.support+0.15 {
			rank = 0
		}
		sz := s.za + (s.zb-s.za)*t
		if rank < bestRank || (rank == bestRank && (d < bestD-1e-9 || (math.Abs(d-bestD) <= 1e-9 && sz > bestZ))) {
			bestRank, bestD, bestZ, edge = rank, d, sz, s.edge
		}
	}
	return edge, bestZ, edge >= 0
}

// validateWaterTerrain: no terrain grid node inside water lies above the water level, except a
// node that carries the strip of a ground road on the bank (an 8 m cell cannot step from the
// road down to the water; the water surface covers that sliver).
func (e *Env) validateWaterTerrain(p *PackData, t *packTerrain, water *meshIndex, ci *conformIndex, fail func(string, ...any)) {
	cm := t.chunkM
	n, bank, worst := 0, 0, 0.0
	var worstAt geo.Pt
	keys := make([][2]int, 0, len(t.z))
	for k := range t.z {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(a, b int) bool {
		if keys[a][1] != keys[b][1] {
			return keys[a][1] < keys[b][1]
		}
		return keys[a][0] < keys[b][0]
	})
	for _, k := range keys {
		zs := t.z[k]
		for j := 0; j < t.n; j++ {
			for i := 0; i < t.n; i++ {
				q := geo.Pt{X: float64(k[0])*cm + float64(i)*t.step, Y: float64(k[1])*cm + float64(j)*t.step}
				w, ok := water.at(q)
				if !ok {
					continue
				}
				over := float64(zs[j*t.n+i]-int16(w.ZDm)) / 10
				if over <= 0.05 {
					continue
				}
				if _, _, ok := ci.assign(q, true, -1); ok {
					bank++
					continue
				}
				n++
				if over > worst {
					worst, worstAt = over, q
				}
			}
		}
	}
	slog.Info("validate: terrain in water", "above_level", n, "max_m", fmt.Sprintf("%.2f", worst), "at", fmt.Sprintf("%.0f,%.0f", worstAt.X, worstAt.Y), "bank_road_nodes", bank)
	if n > 0 {
		fail("%d terrain samples in water lie above the water level (max %.1f m at %.0f, %.0f)", n, worst, worstAt.X, worstAt.Y)
	}
}

// validateRoadStrips samples the carriageway of every kept ground road (4 m along, five points
// across) and compares the bilinear terrain with the road profile (terrain.pipeline.road_strip).
// Skipped: points on another road's corridor (junctions) and points whose cell has a corner that
// carries another road, or another leg of this one, at a different height (one node cannot carry
// two profiles; counted as contested).
func (e *Env) validateRoadStrips(p *PackData, t *packTerrain, water *meshIndex, ground *groundSegs, ci *conformIndex, fail func(string, ...any)) {
	g := p.Graph
	rs := e.C.Tuning.Terrain.Pipeline.RoadStrip
	type stat struct {
		n, over int
		max     float64
		devs    []float64
	}
	var all, region stat
	var reg [4]float64
	hasReg := false
	if r := os.Getenv("CITYPACK_REGION"); r != "" {
		if _, err := fmt.Sscanf(r, "%f,%f,%f,%f", &reg[0], &reg[1], &reg[2], &reg[3]); err == nil {
			hasReg = true
		}
	}
	add := func(s *stat, d float64) {
		s.n++
		s.devs = append(s.devs, d)
		if math.Abs(d) > rs.TolM {
			s.over++
		}
		s.max = math.Max(s.max, math.Abs(d))
	}
	// contested: a corner of q's cell carries another road at a different height. The same street can come back within a cell (a hairpin: Na Václavce, Na Hřebenkách): a
	// corner whose nearest point of this edge lies more than two cell diagonals away along the
	// route, at another height, carries another leg of the road.
	hairpin := 2 * t.step * math.Sqrt2
	contestedAt := func(q geo.Pt, edge int, pts []geo.Pt, zs, cum []float64, sq float64, zq float64) bool {
		x0, y0 := math.Floor(q.X/t.step)*t.step, math.Floor(q.Y/t.step)*t.step
		for _, c := range []geo.Pt{{X: x0, Y: y0}, {X: x0 + t.step, Y: y0}, {X: x0, Y: y0 + t.step}, {X: x0 + t.step, Y: y0 + t.step}} {
			_, inW := water.at(c)
			we, wz, ok := ci.assign(c, inW, -1)
			if !ok {
				continue
			}
			if we != edge {
				if _, oz, ok := ci.assign(c, inW, edge); !ok || math.Abs(oz-wz) > 0.05 {
					return true
				}
				continue
			}
			bd, bs, bz := math.Inf(1), 0.0, 0.0
			for k := 1; k < len(pts); k++ {
				cp, tq := geo.ClosestOnSegment(c, pts[k-1], pts[k])
				if d := cp.Dist(c); d < bd {
					bd, bs, bz = d, cum[k-1]+tq*(cum[k]-cum[k-1]), zs[k-1]+(zs[k]-zs[k-1])*tq
				}
			}
			if math.Abs(bs-sq) > hairpin && math.Abs(bz-zq) > rs.TolM {
				return true
			}
		}
		return false
	}
	worstEdge, worst := -1, 0.0
	var worstAt geo.Pt
	contested := 0
	overBy := map[string]int{} // street name → samples over tol
	for i, ed := range g.Edges {
		if !ed.Kept || !groundEdge(ed) {
			continue
		}
		pts, zs := EdgePts(ed), edgeZ(ed)
		if len(zs) != len(pts) {
			continue
		}
		hc := carriageway(ed, e.C.Tuning.SidewalkWidthM)
		cum := make([]float64, len(pts))
		for k := 1; k < len(pts); k++ {
			cum[k] = cum[k-1] + pts[k].Dist(pts[k-1])
		}
		for k := 1; k < len(pts); k++ {
			a, b := pts[k-1], pts[k]
			l := a.Dist(b)
			if l < 1e-6 {
				continue
			}
			nrm := geo.Pt{X: -(b.Y - a.Y) / l, Y: (b.X - a.X) / l}
			for s := 0.0; s <= l; s += 4 {
				c := a.Add(b.Sub(a).Mul(s / l))
				z := zs[k-1] + (zs[k]-zs[k-1])*s/l
				for _, f := range []float64{-1, -0.5, 0, 0.5, 1} {
					q := c.Add(nrm.Mul(f * hc))
					tz, ok := t.at(q)
					if !ok || ground.ownedByOther(q, i, z, 0, 0) {
						continue
					}
					if contestedAt(q, i, pts, zs, cum, cum[k-1]+s, z) {
						contested++
						continue
					}
					d := tz - z
					add(&all, d)
					if math.Abs(d) > rs.TolM {
						overBy[g.Names[ed.Name]]++
					}
					if hasReg && q.X >= reg[0] && q.Y >= reg[1] && q.X <= reg[2] && q.Y <= reg[3] {
						add(&region, d)
					}
					if math.Abs(d) > worst {
						worst, worstEdge, worstAt = math.Abs(d), i, q
					}
				}
			}
		}
	}
	report := func(name string, s stat) {
		if s.n == 0 {
			return
		}
		sort.Float64s(s.devs)
		q := func(f float64) float64 { return s.devs[int(f*float64(len(s.devs)-1))] }
		slog.Info("validate: road strip vs terrain "+name, "samples", s.n, "over_m", rs.TolM, "count", s.over,
			"min_m", fmt.Sprintf("%.2f", s.devs[0]), "p01", fmt.Sprintf("%.2f", q(0.01)), "p99", fmt.Sprintf("%.2f", q(0.99)),
			"max_m", fmt.Sprintf("%.2f", s.devs[len(s.devs)-1]))
	}
	report("(all kept)", all)
	slog.Info("validate: road strip samples on a node shared with a road at another height (skipped)", "count", contested)
	if hasReg {
		report("(region)", region)
	}
	// Tight bends on steep serpentines (Na Václavce, Na Hřebenkách) bend the profile inside one
	// 8 m cell, which bilinear sampling cannot follow: a small share may exceed tol_m, nothing
	// may exceed max_m.
	if all.over > 0 {
		type sc struct {
			name string
			n    int
		}
		var top []sc
		for n, c := range overBy {
			top = append(top, sc{n, c})
		}
		sort.Slice(top, func(a, b int) bool {
			if top[a].n != top[b].n {
				return top[a].n > top[b].n
			}
			return top[a].name < top[b].name
		})
		for _, x := range top[:min(8, len(top))] {
			slog.Info("validate: road strip over tol", "street", x.name, "samples", x.n)
		}
	}
	name := ""
	if worstEdge >= 0 {
		name = g.Names[g.Edges[worstEdge].Name]
	}
	if all.n > 0 && float64(all.over) > rs.Share*float64(all.n) {
		fail("%d of %d road strip samples differ from the terrain by more than %.2f m (limit %.1f %%)", all.over, all.n, rs.TolM, 100*rs.Share)
	}
	if worst > rs.MaxM {
		fail("road strip sample %.2f m from the terrain (max %.1f m), %s at %.0f, %.0f", worst, rs.MaxM, name, worstAt.X, worstAt.Y)
	}
}
