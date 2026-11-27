package steps

import (
	"bytes"
	"compress/gzip"
	"fmt"
	"io"
	"log/slog"
	"math"
	"os"
	"path/filepath"
	"slices"

	"citypack/internal/geo"
	"citypack/internal/pb"

	"google.golang.org/protobuf/proto"
)

// validateModels checks models.pb (specs/models.md, plan ch. 6 "Validate" and ch. 8 budgets).
// A pack without models.pb passes.
func (e *Env) validateModels(p *PackData, fail func(string, ...any)) {
	path := filepath.Join(e.Out, "models.pb")
	raw, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		if p.Manifest.ModelsVersion != 0 {
			fail("manifest models_version %d without models.pb", p.Manifest.ModelsVersion)
		}
		return
	}
	if err != nil {
		fail("models.pb: %v", err)
		return
	}
	ms, err := decodeModels(raw)
	if err != nil {
		fail("models.pb: %v", err)
		return
	}
	if p.Manifest.ModelsVersion != ModelsVersion {
		fail("manifest models_version %d, want %d", p.Manifest.ModelsVersion, ModelsVersion)
	}
	mt := e.C.Tuning.Models
	if len(raw) > mt.CityMaxBytes {
		fail("models.pb %d B over models.city_max_bytes %d", len(raw), mt.CityMaxBytes)
	}
	exag := float64(p.Manifest.Exaggeration)
	if exag <= 0 {
		exag = 1
	}
	pt := newPackTerrain(p)
	chunks := map[[2]int]*pb.Chunk{}
	for _, c := range p.Chunks {
		chunks[[2]int{int(c.X), int(c.Y)}] = c
	}
	total := 0
	for _, m := range ms.Models {
		total += int(m.Tris)
		budget := mt.MaxTris
		if e.C.Models != nil {
			if mc, ok := e.C.Models.Models[m.LandmarkId]; ok && mc.MaxTris > 0 {
				budget = min(mc.MaxTris, mt.MaxTrisException)
			}
		}
		lm := -1
		for i, l := range p.Landmarks.Items {
			if l.Id == m.LandmarkId {
				lm = i
			}
		}
		if lm < 0 {
			fail("model %s: no such landmark", m.LandmarkId)
			continue
		}
		if a := ModelAttribution(m.Source); a == "" || !slices.Contains(p.Manifest.Attribution, a) {
			fail("model %s: source %v has no attribution in the manifest", m.LandmarkId, m.Source)
		}
		tris, deep, maxBuried := 0, 0, 0.0
		var cx, cy, cw float64
		for pi, part := range m.Parts {
			nv := uint32(len(part.Positions) / 3)
			nt := len(part.Triangles) / 3
			tris += nt
			if len(part.Triangles)%3 != 0 || len(part.Roles) != nt || len(part.Positions)%3 != 0 {
				fail("model %s part %d: %d indices, %d roles, %d coordinates", m.LandmarkId, pi, len(part.Triangles), len(part.Roles), len(part.Positions))
				continue
			}
			for _, i := range part.Triangles {
				if i >= nv {
					fail("model %s part %d: index %d over %d vertices", m.LandmarkId, pi, i, nv)
					break
				}
			}
			for _, r := range part.Roles {
				if r > byte(pb.ModelRole_ROLE_SLATE) {
					fail("model %s part %d: unknown role %d", m.LandmarkId, pi, r)
					break
				}
			}
			// v2: one surface class per triangle (specs/models.md).
			if len(part.Surfaces) != nt {
				fail("model %s part %d: %d surfaces for %d triangles", m.LandmarkId, pi, len(part.Surfaces), nt)
			}
			for _, s := range part.Surfaces {
				if s > byte(pb.ModelSurface_SURFACE_ROOF) {
					fail("model %s part %d: unknown surface %d", m.LandmarkId, pi, s)
					break
				}
			}
			anchor := geo.Pt{X: float64(part.AnchorX) / 10, Y: float64(part.AnchorY) / 10}
			w := float64(nt)
			cx, cy, cw = cx+anchor.X*w, cy+anchor.Y*w, cw+w
			if pt != nil {
				// The foot stands on the terrain: wall bottoms (lowest vertex of every column with
				// a vertical edge) vs the terrain under them, median in real metres.
				// No foot vertex may hover; burial (uphill side, coarse DEM) is only reported.
				if float, buried, ok := footGap(part, pt, exag); ok {
					if float > mt.FootTolM {
						fail("model %s part %s: foot %.1f m above the terrain (> %.1f)", m.LandmarkId, part.SourceId, float, mt.FootTolM)
					}
					if buried > mt.FootTolM {
						deep++
					}
					maxBuried = math.Max(maxBuried, buried)
				}
			}
		}
		if tris != int(m.Tris) {
			fail("model %s: tris %d, counted %d", m.LandmarkId, m.Tris, tris)
		}
		if tris > budget {
			fail("model %s: %d triangles over the budget %d", m.LandmarkId, tris, budget)
		}
		if len(m.RoofPlan) > mt.RoofPlanMaxPolys {
			fail("model %s: roof plan %d polygons over %d", m.LandmarkId, len(m.RoofPlan), mt.RoofPlanMaxPolys)
		}
		for _, pp := range m.RoofPlan {
			n := uint32(len(pp.Points) / 2)
			if len(pp.RingEnds) == 0 || pp.RingEnds[len(pp.RingEnds)-1] != n || pp.Shade > 3 || len(pp.Triangles)%3 != 0 {
				fail("model %s: malformed roof plan polygon", m.LandmarkId)
				break
			}
		}
		l := p.Landmarks.Items[lm]
		if cw > 0 {
			c := geo.Pt{X: cx / cw, Y: cy / cw}
			if d := c.Dist(geo.Pt{X: float64(l.X) / 10, Y: float64(l.Y) / 10}); d > mt.MaxOffsetM {
				fail("model %s: centre %.0f m from the landmark point (> %.0f)", m.LandmarkId, d, mt.MaxOffsetM)
			}
		}
		for _, r := range m.Replaces {
			c, ok := chunks[[2]int{int(r.ChunkX), int(r.ChunkY)}]
			if !ok || int(r.Index) >= len(c.Buildings) {
				fail("model %s: replaces a missing building %d_%d #%d", m.LandmarkId, r.ChunkX, r.ChunkY, r.Index)
			}
		}
		if deep > 0 {
			slog.Warn("validate: model parts buried deeper than foot_tolerance_m (median; DEM vs source ground, warning only)",
				"id", m.LandmarkId, "parts", deep, "max_m", fmt.Sprintf("%.1f", maxBuried))
		}
		slog.Info("validate: model", "id", m.LandmarkId, "tris", tris, "budget", budget, "parts", len(m.Parts),
			"plan_polys", len(m.RoofPlan), "replaces", len(m.Replaces))
	}
	if total > mt.CityMaxTris {
		fail("models: %d triangles over models.city_max_tris %d", total, mt.CityMaxTris)
	}
	slog.Info("validate: models", "count", len(ms.Models), "tris", total, "bytes", len(raw))
}

func decodeModels(gz []byte) (*pb.Models, error) {
	zr, err := gzip.NewReader(bytes.NewReader(gz))
	if err != nil {
		return nil, err
	}
	b, err := io.ReadAll(zr)
	if err != nil {
		return nil, err
	}
	ms := &pb.Models{}
	return ms, proto.Unmarshal(b, ms)
}

// footGap returns how far the part's foot vertices hover above the terrain at most and how deep
// they are buried in the median, in real metres.
func footGap(part *pb.ModelPart, pt *packTerrain, exag float64) (float64, float64, bool) {
	var buried []float64
	hover := 0.0
	for _, i := range part.Foot {
		if int(3*i+2) >= len(part.Positions) {
			continue
		}
		q := geo.Pt{X: float64(part.AnchorX+part.Positions[3*i]) / 10, Y: float64(part.AnchorY+part.Positions[3*i+1]) / 10}
		z, ok := pt.at(q)
		if !ok {
			continue
		}
		d := (z - float64(part.BaseZDm+part.Positions[3*i+2])/10) / exag
		hover = math.Max(hover, -d)
		buried = append(buried, math.Max(0, d))
	}
	if len(buried) == 0 {
		return 0, 0, false
	}
	slices.Sort(buried)
	return hover, buried[len(buried)/2], true
}
