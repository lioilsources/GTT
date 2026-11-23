package steps

import (
	"fmt"
	"log/slog"
	"math"
	"os"
	"sort"
	"strings"

	"citypack/internal/geo"
)

// validateTrench: next to a ground road the terrain never rises above the road surface, so a
// street does not sit in a trench and the houses along it are not buried (oblique view,
// Nerudova). Samples every 4 m along each ground edge at the corridor edge (road width / 2) and
// terrain.pipeline.trench.margin_m beyond it, both sides; terrain − road z ≤ max_m except for
// a share of samples.
// Skipped: points in another road's corridor, and points near another ground road that is
// itself higher (its own corridor lifts the terrain legitimately).
func (e *Env) validateTrench(p *PackData, t *packTerrain, ground *groundSegs, fail func(string, ...any)) {
	g := p.Graph
	tr := e.C.Tuning.Terrain.Pipeline.Trench
	diag := t.step * math.Sqrt2
	type region struct {
		name           string
		x0, y0, x1, y1 float64
		n, over        int
		max            float64
	}
	var regs []*region
	for _, r := range strings.Split(os.Getenv("CITYPACK_REGIONS"), ";") {
		var rg region
		name, box, ok := strings.Cut(r, ":")
		if !ok {
			continue
		}
		if _, err := fmt.Sscanf(box, "%f,%f,%f,%f", &rg.x0, &rg.y0, &rg.x1, &rg.y1); err == nil {
			rg.name = name
			regs = append(regs, &rg)
		}
	}
	n, over, worst := 0, 0, 0.0
	var worstAt geo.Pt
	worstName := ""
	overBy := map[string]int{}
	higherNear := func(q geo.Pt, edge int, z float64) bool {
		c := cellOf(q)
		for dx := -1; dx <= 1; dx++ {
			for dy := -1; dy <= 1; dy++ {
				for _, k := range ground.grid[[2]int{c[0] + dx, c[1] + dy}] {
					s := ground.segs[k]
					if s.edge == edge {
						continue
					}
					cq, tq := geo.ClosestOnSegment(q, s.a, s.b)
					if cq.Dist(q) < s.hw+tr.MarginM+diag && s.za+(s.zb-s.za)*tq > z+tr.MaxM {
						return true
					}
				}
			}
		}
		return false
	}
	for i, ed := range g.Edges {
		if !groundEdge(ed) {
			continue
		}
		pts, zs := EdgePts(ed), edgeZ(ed)
		if len(zs) != len(pts) {
			continue
		}
		hw := float64(ed.WidthM) / 2
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
				for _, off := range []float64{-hw - tr.MarginM, -hw, hw, hw + tr.MarginM} {
					q := c.Add(nrm.Mul(off))
					tz, ok := t.at(q)
					if !ok || ground.ownedByOther(q, i, z, 0, 0) || higherNear(q, i, z) {
						continue
					}
					d := tz - z
					n++
					if d > tr.MaxM {
						over++
						overBy[g.Names[ed.Name]]++
					}
					if d > worst {
						worst, worstAt, worstName = d, q, g.Names[ed.Name]
					}
					for _, r := range regs {
						if q.X >= r.x0 && q.Y >= r.y0 && q.X <= r.x1 && q.Y <= r.y1 {
							r.n++
							if d > tr.MaxM {
								r.over++
							}
							r.max = math.Max(r.max, d)
						}
					}
				}
			}
		}
	}
	slog.Info("validate: terrain above road next to it", "samples", n, "over_m", tr.MaxM, "count", over, "max_m", fmt.Sprintf("%.2f", worst), "street", worstName, "at", fmt.Sprintf("%.0f,%.0f", worstAt.X, worstAt.Y))
	for _, r := range regs {
		slog.Info("validate: terrain above road (region)", "region", r.name, "samples", r.n, "count", r.over, "max_m", fmt.Sprintf("%.2f", r.max))
	}
	if over > 0 {
		type sc struct {
			name string
			n    int
		}
		var top []sc
		for k, v := range overBy {
			top = append(top, sc{k, v})
		}
		sort.Slice(top, func(a, b int) bool {
			if top[a].n != top[b].n {
				return top[a].n > top[b].n
			}
			return top[a].name < top[b].name
		})
		for _, x := range top[:min(8, len(top))] {
			slog.Info("validate: terrain above road", "street", x.name, "samples", x.n)
		}
	}
	// Where two roads at different heights share grid cells (a junction on a steep street, a
	// service road beside a climbing street) one terrain cannot meet both: a small share may
	// exceed max_m (terrain.pipeline.trench.share).
	if n > 0 && float64(over) > tr.Share*float64(n) {
		fail("%d of %d samples beside ground roads have terrain more than %.1f m above the road (limit %.1f %%; max %.2f m, %s at %.0f, %.0f)", over, n, tr.MaxM, 100*tr.Share, worst, worstName, worstAt.X, worstAt.Y)
	}
}
