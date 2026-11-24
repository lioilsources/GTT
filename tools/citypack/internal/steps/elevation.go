package steps

import (
	"encoding/gob"
	"fmt"
	"log/slog"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"citypack/internal/dem"
	"citypack/internal/geo"
	"citypack/internal/pb"
	"citypack/internal/terrain"

	"google.golang.org/protobuf/proto"
)

// demFloorM: DEM samples below this are no data.
const demFloorM = -100.0

// TerrainVersion is Manifest.terrain_version written by packs with elevation (specs/terrain.md v1).
const TerrainVersion = 1

// TerrainGrid is terrain.bin: game heights (dm) and shade over the whole chunk range at grid_m.
type TerrainGrid struct {
	CX0, CY0 int // first chunk
	W, H     int // samples
	Step     float64
	ChunkM   float64
	Z        []int16
	Shade    []uint8
}

// At returns the game height in metres at a local point (bilinear, clamped).
func (t *TerrainGrid) At(p geo.Pt) float64 {
	x := (p.X - float64(t.CX0)*t.ChunkM) / t.Step
	y := (p.Y - float64(t.CY0)*t.ChunkM) / t.Step
	i0, j0 := math.Floor(x), math.Floor(y)
	fx, fy := x-i0, y-j0
	get := func(i, j int) float64 {
		i = max(0, min(t.W-1, i))
		j = max(0, min(t.H-1, j))
		return float64(t.Z[j*t.W+i]) / 10
	}
	i, j := int(i0), int(j0)
	a := get(i, j)*(1-fx) + get(i+1, j)*fx
	b := get(i, j+1)*(1-fx) + get(i+1, j+1)*fx
	return a*(1-fy) + b*fy
}

// ElevationReport is elevation.json.
type ElevationReport struct {
	Source       string
	Z0           float64
	Exaggeration float64
	Clamped      int
	Passes       int
	ResidualM    float64
	Stairs       []string
	WaterLevels  map[string]float64 // waterKey → game height (m)
	MinZ, MaxZ   float64            // game terrain range (m)
}

// waterKey groups water pieces into bodies with one level: named pieces by class and name,
// unnamed ones per piece.
func waterKey(w NaturePiece, i int) string {
	if w.Name != "" {
		return fmt.Sprintf("%d/%s", w.Class, w.Name)
	}
	return fmt.Sprintf("%d/#%d_%d_%d", w.Class, w.CX, w.CY, i)
}

// Elevation runs the terrain step (Prompts/02-METROPOLE_TERRAIN_PLAN.md ch. 4): dem → clean →
// profile → pins → exaggerate → grade_clamp → conform → shade. Without elevation sources the
// pack stays flat (outputs are removed).
func Elevation(e *Env) error {
	out := e.W("elevation.json")
	outs := []string{out, e.W("graph_z.pb"), e.W("terrain.bin")}
	if len(e.C.City.ElevationSources) == 0 {
		for _, f := range outs {
			_ = os.Remove(f)
		}
		slog.Info("elevation: no elevation_sources, pack stays flat")
		return nil
	}
	if e.fresh(out) {
		skip("elevation", out)
		return nil
	}
	tt := e.C.Tuning.Terrain
	tp := tt.Pipeline
	var src dem.Sampler
	for _, s := range e.C.City.ElevationSources {
		switch s {
		case "local":
			l, err := dem.LocalASC(filepath.Join(e.C.City.Dir, "dem"))
			if err != nil {
				return err
			}
			if l != nil {
				src = l
			}
		case "terrain_tiles":
			minLon, minLat, maxLon, maxLat := e.C.City.BBox()
			// Margin in degrees (generous: the tiles are cached).
			dLat := tp.DemMarginM / geo.EarthR * 180 / math.Pi
			dLon := dLat / math.Cos(e.C.City.Origin.Lat*math.Pi/180)
			b := dem.BBox{LatMin: minLat - 2*dLat, LonMin: minLon - 2*dLon, LatMax: maxLat + 2*dLat, LonMax: maxLon + 2*dLon}
			t, err := dem.TerrainTiles(b, tp.DemZoom, e.W("tiles"))
			if err != nil {
				return err
			}
			src = t
		case "gsi_tiles":
			minLon, minLat, maxLon, maxLat := e.C.City.BBox()
			dLat := tp.DemMarginM / geo.EarthR * 180 / math.Pi
			dLon := dLat / math.Cos(e.C.City.Origin.Lat*math.Pi/180)
			b := dem.BBox{LatMin: minLat - 2*dLat, LonMin: minLon - 2*dLon, LatMax: maxLat + 2*dLat, LonMax: maxLon + 2*dLon}
			t, err := dem.GSITiles(b, tp.DemZoom, e.W("tiles_gsi"))
			if err != nil {
				return err
			}
			src = t
		default:
			return fmt.Errorf("city.yaml: unknown elevation source %q", s)
		}
		if src != nil {
			break
		}
	}
	if src == nil {
		return fmt.Errorf("no elevation source available (%v)", e.C.City.ElevationSources)
	}
	g, err := e.LoadGraph()
	if err != nil {
		return err
	}
	masses, err := e.LoadMasses()
	if err != nil {
		return err
	}
	water, err := e.loadWaterForTerrain()
	if err != nil {
		return err
	}

	// 1. dem: 4 m working grid in local metres over the chunk range plus the margin.
	cm := float64(e.C.Tuning.ChunkM)
	cx0, cy0, cx1, cy1 := e.chunkRange()
	x0, y0 := float64(cx0)*cm-tp.DemMarginM, float64(cy0)*cm-tp.DemMarginM
	w := int(math.Ceil((float64(cx1-cx0+1)*cm+2*tp.DemMarginM)/tp.DemGridM)) + 1
	h := int(math.Ceil((float64(cy1-cy0+1)*cm+2*tp.DemMarginM)/tp.DemGridM)) + 1
	r := terrain.NewRaster(x0, y0, tp.DemGridM, w, h)
	mask := make([]bool, len(r.Z))
	missing := 0
	for j := 0; j < h; j++ {
		for i := 0; i < w; i++ {
			lon, lat := e.Proj.Inverse(r.Pos(i, j))
			z, ok := src.At(lon, lat)
			// Terrarium tiles carry occasional bogus bathymetry (thousands of metres deep in the
			// East River); nothing in a city lies that low, so treat it as no data.
			if !ok || z < demFloorM {
				mask[j*w+i] = true
				missing++
				continue
			}
			r.Set(i, j, z)
		}
	}
	if missing > 0 {
		r.Fill(mask)
	}
	{
		lo, hi := math.Inf(1), math.Inf(-1)
		for _, z := range r.Z {
			lo, hi = math.Min(lo, z), math.Max(hi, z)
		}
		slog.Info("elevation: dem", "source", src.Name(), "cells", len(r.Z), "filled", missing, "range_m", fmt.Sprintf("%.1f..%.1f", lo, hi))
	}
	// 2. clean: a surface model loses its buildings, then smooths.
	if !e.C.City.BareEarth() {
		bm := make([]bool, len(r.Z))
		for _, m := range masses {
			if m.MinH >= 0.5 {
				continue
			}
			minX, minY, maxX, maxY := bounds(m.Rings[0])
			for j := max(0, int((minY-y0)/tp.DemGridM)); j <= min(h-1, int((maxY-y0)/tp.DemGridM)+1); j++ {
				for i := max(0, int((minX-x0)/tp.DemGridM)); i <= min(w-1, int((maxX-x0)/tp.DemGridM)+1); i++ {
					if geo.PointInRing(r.Pos(i, j), m.Rings[0]) {
						bm[j*w+i] = true
					}
				}
			}
		}
		r.Fill(bm)
		sigma := tp.CleanSigmaM
		if !src.Lidar() {
			sigma = tp.CleanSigmaCoarseM
		}
		r.Blur(sigma)
	}
	ground := func(p geo.Pt) float64 { return r.Bilinear(p) }

	// Water levels (real metres): sea at 0, others from their banks.
	levels := waterLevels(water, ground, cm)
	// city.yaml water_level_m: a known level wins over the banks (a tidal river below a surface
	// model's bluffs: Tokyo's Kanda-gawa).
	for i, w := range water {
		if v, ok := e.C.City.WaterLevelM[w.Name]; ok && w.Name != "" {
			levels[waterKey(w, i)] = v
		}
	}
	wi := newWaterIndex(water, levels)

	// z0: the lowest of sea level (if the city has sea) and the 1st percentile of node heights.
	nz := make([]float64, 0, len(g.Nodes))
	for _, n := range g.Nodes {
		nz = append(nz, ground(geo.Pt{X: float64(n.X) / 10, Y: float64(n.Y) / 10}))
	}
	sort.Float64s(nz)
	z0 := nz[len(nz)/100]
	for _, l := range levels {
		z0 = math.Min(z0, l)
	}
	z0 = math.Floor(z0)

	// 3–6. profile, pins, exaggerate, grade_clamp.
	window := tp.ProfileWindowM.Coarse
	if src.Lidar() {
		window = tp.ProfileWindowM.Lidar
	}
	params := terrain.Params{
		Exaggeration: tt.Exaggeration, MaxGrade: tt.MaxGrade,
		ClearWaterM: tt.Bridge.ClearWaterM, ClearRoadM: tt.Bridge.ClearRoadM, BridgeGrade: tt.Bridge.MaxGrade,
		DepthWaterM: tt.Tunnel.DepthWaterM, DepthLandM: tt.Tunnel.DepthLandM, TunnelGrade: tt.Tunnel.MaxGrade,
		StepM: tp.ProfileStepM, WindowM: window, ElevatedM: tp.ElevatedM,
		GradeTolM: tp.GradeTolM, GradePasses: tp.GradePasses, ZTolM: tp.ZTolM, FairPasses: tp.ProfileFairPasses,
	}
	decks := map[string]float64{}
	for _, l := range e.C.Landmarks {
		if l.DeckHeightM > 0 {
			decks[l.Name] = l.DeckHeightM
		}
	}
	flagWaterBridges(g, wi, tp.BridgeOverWaterM)
	in := terrain.Input{Ground: ground, Z0: z0, Water: wi.level}
	for _, n := range g.Nodes {
		in.Nodes = append(in.Nodes, geo.Pt{X: float64(n.X) / 10, Y: float64(n.Y) / 10})
	}
	for _, ed := range g.Edges {
		te := terrain.Edge{From: int(ed.From), To: int(ed.To), Pts: EdgePts(ed), Class: gradeClass(ed),
			LayerFrom: profileLayer(ed, ed.LayerFrom), LayerTo: profileLayer(ed, ed.LayerTo), HalfWidthM: float64(ed.WidthM) / 2, Bridge: ed.Bridge, Tunnel: ed.Tunnel, Kept: ed.Kept}
		if ed.Bridge {
			te.DeckM = decks[g.Names[ed.Name]]
		}
		// The pipeline keeps the first/last point equal to the node; trust the node position.
		te.Pts[0], te.Pts[len(te.Pts)-1] = in.Nodes[ed.From], in.Nodes[ed.To]
		in.Edges = append(in.Edges, te)
	}
	res := terrain.Profile(in, params)

	// 7. conform (run here, before graph_z, because the deck check below reads its result).
	gm := tt.GridM
	per := int(math.Round(cm / gm))
	gameWater := func(p geo.Pt) (float64, bool) {
		l, ok := wi.level(p)
		return (l - z0) * tt.Exaggeration, ok
	}
	// Bathymetry outside the mapped water (past the area, under piers) is never shown deeper than
	// the water floor.
	floor := math.Inf(-1)
	for _, l := range levels {
		if math.IsInf(floor, -1) || (l-z0)*tt.Exaggeration-tp.UnderwaterM < floor {
			floor = (l-z0)*tt.Exaggeration - tp.UnderwaterM
		}
	}
	conform := func(res terrain.Result) *terrain.Raster {
		tg := terrain.NewRaster(float64(cx0)*cm, float64(cy0)*cm, gm, (cx1-cx0+1)*per+1, (cy1-cy0+1)*per+1)
		var roads []terrain.Road
		// Only ground edges shape the terrain. Clients ride the edge's own surface on bridges (also
		// Overture bridges on level 0, Mánesův most), ramps and tunnels (specs/terrain.md groundZ),
		// so the terrain under them keeps its own shape and the river under a deck stays flat.
		for ei, pts := range res.EdgePts {
			te := in.Edges[ei]
			if te.Bridge || te.Tunnel || te.LayerFrom != 0 || te.LayerTo != 0 {
				continue
			}
			for k := 1; k < len(pts); k++ {
				if res.GroundPt[ei][k-1] && res.GroundPt[ei][k] {
					roads = append(roads, terrain.Road{A: pts[k-1], B: pts[k], ZA: res.EdgeZ[ei][k-1], ZB: res.EdgeZ[ei][k], HalfWidthM: te.HalfWidthM,
						StripM: carriageway(g.Edges[ei], e.C.Tuning.SidewalkWidthM), Kept: g.Edges[ei].Kept, Edge: ei})
				}
			}
		}
		terrain.Conform(tg, func(p geo.Pt) float64 { return math.Max(floor, (ground(p)-z0)*tt.Exaggeration) }, gameWater, roads,
			terrain.ConformParams{SupportM: gm * math.Sqrt2, MarginM: tp.Trench.MarginM, BlendM: tt.BlendM, UnderwaterM: tp.UnderwaterM, FitStepM: tp.ConformFit.StepM, FitPasses: tp.ConformFit.Passes})
		return tg
	}
	tg := conform(res)
	// A ground edge that leaves a deck in the air (its nodes went to another road below, NYC West
	// 38th Street over the Lincoln Tunnel approach) becomes a bridge; profile and conform again.
	if n := flagElevated(g, in.Edges, res, tg.Bilinear, tp.ElevatedFlag.AboveM, tp.ElevatedFlag.RunM); n > 0 {
		slog.Info("elevation: unflagged deck ends flagged as bridges, profile and conform again", "edges", n)
		res = terrain.Profile(in, params)
		tg = conform(res)
	}

	gz := proto.Clone(g).(*pb.Graph)
	for i, n := range gz.Nodes {
		n.ZDm = geo.DM(res.NodeZ[i])
	}
	rep := ElevationReport{Source: src.Name(), Z0: z0, Exaggeration: tt.Exaggeration, Clamped: res.Clamped,
		Passes: res.Passes, ResidualM: res.Residual, WaterLevels: map[string]float64{}}
	for ei, ed := range gz.Edges {
		ed.Points = ed.Points[:0]
		ed.ZDm = ed.ZDm[:0]
		for k, p := range res.EdgePts[ei] {
			ed.Points = append(ed.Points, geo.DM(p.X), geo.DM(p.Y))
			ed.ZDm = append(ed.ZDm, geo.DM(res.EdgeZ[ei][k]))
		}
		// Ends carry the node height exactly.
		ed.ZDm[0], ed.ZDm[len(ed.ZDm)-1] = gz.Nodes[ed.From].ZDm, gz.Nodes[ed.To].ZDm
		if res.Stairs[ei] {
			ed.Stairs = true
			rep.Stairs = append(rep.Stairs, fmt.Sprintf("%d %s", ei, g.Names[ed.Name]))
			if os.Getenv("CITYPACK_DEBUG") != "" {
				l := geo.PolylineLength(res.EdgePts[ei])
				zs := res.EdgeZ[ei]
				slog.Info("stairs", "edge", ei, "name", g.Names[ed.Name], "class", ed.Class, "kept", ed.Kept, "layers", fmt.Sprint(ed.LayerFrom, ed.LayerTo),
					"bridge", ed.Bridge, "tunnel", ed.Tunnel, "len", int(l), "z", fmt.Sprintf("%.1f..%.1f", zs[0], zs[len(zs)-1]),
					"x", g.Nodes[ed.From].X/10, "y", g.Nodes[ed.From].Y/10)
			}
		}
	}
	for k, l := range levels {
		rep.WaterLevels[k] = (l - z0) * tt.Exaggeration
	}

	// 8. shade.
	grid := TerrainGrid{CX0: cx0, CY0: cy0, W: tg.W, H: tg.H, Step: gm, ChunkM: cm, Z: make([]int16, len(tg.Z)),
		Shade: tg.ShadeZ(tp.Sun.AzimuthDeg, tp.Sun.AltitudeDeg, tp.ShadeStrength)}
	rep.MinZ, rep.MaxZ = math.Inf(1), math.Inf(-1)
	for k, z := range tg.Z {
		dm := math.Round(z * 10)
		if dm < math.MinInt16 || dm > math.MaxInt16 {
			p := tg.Pos(k%tg.W, k/tg.W)
			return fmt.Errorf("terrain height %.1f m at (%.0f, %.0f) does not fit int16 dm (z0 %.1f, dem %.1f)", z, p.X, p.Y, z0, ground(p))
		}
		grid.Z[k] = int16(dm)
		rep.MinZ, rep.MaxZ = math.Min(rep.MinZ, z), math.Max(rep.MaxZ, z)
	}
	f, err := os.Create(e.W("terrain.bin"))
	if err != nil {
		return err
	}
	if err := gob.NewEncoder(f).Encode(&grid); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	b, err := proto.Marshal(gz)
	if err != nil {
		return err
	}
	if err := os.WriteFile(e.W("graph_z.pb"), b, 0o644); err != nil {
		return err
	}
	if res.Residual > tp.GradeTolM {
		slog.Warn("elevation: grade conflict", "worst", res.Worst)
	}
	slog.Info("elevation", "source", rep.Source, "z0", z0, "clamped", rep.Clamped, "passes", rep.Passes, "relaxed_pins", res.Relaxed,
		"residual_m", fmt.Sprintf("%.3f", rep.ResidualM), "stairs", len(rep.Stairs),
		"terrain_m", fmt.Sprintf("%.1f..%.1f", rep.MinZ, rep.MaxZ))
	return writeJSON(out, rep)
}

// profileLayer is the layer the profile uses: an underpass below ground that is not a tunnel (a
// cutting such as the Central Park transverses) is already in the bare-earth DEM, so it follows
// the ground instead of being pinned below it.
func profileLayer(ed *pb.Edge, l int32) int {
	if l < 0 && !ed.Tunnel {
		return 0
	}
	return int(l)
}

// gradeClass maps a road class to its terrain.max_grade key; everything below tertiary is an alley.
func gradeClass(ed *pb.Edge) string {
	switch ed.Class {
	case pb.RoadClass_MOTORWAY, pb.RoadClass_TRUNK, pb.RoadClass_PRIMARY, pb.RoadClass_SECONDARY, pb.RoadClass_TERTIARY:
		return strings.ToLower(ed.Class.String())
	}
	return "alley"
}

// loadWaterForTerrain prefers the classified nature water, else the ground step's water.
func (e *Env) loadWaterForTerrain() ([]NaturePiece, error) {
	if _, err := os.Stat(e.W("nature_water.jsonl")); err == nil {
		return e.LoadNaturePieces("nature_water.jsonl")
	}
	rows, err := e.LoadGround()
	if err != nil {
		return nil, err
	}
	var out []NaturePiece
	for _, r := range rows {
		if r.Kind == pb.GroundKind_WATER {
			out = append(out, NaturePiece{CX: r.CX, CY: r.CY, Class: int(pb.WaterClass_WATER_LAKE), Rings: r.Rings})
		}
	}
	return out, nil
}

// waterLevels estimates each body's real water level: 0 for the sea, else the lower quartile of
// the DEM along its banks (samples on chunk clip lines and below −1 m bathymetry are skipped).
func waterLevels(water []NaturePiece, ground func(geo.Pt) float64, cm float64) map[string]float64 {
	samples := map[string][]float64{}
	keys := map[string]bool{}
	for i, w := range water {
		k := waterKey(w, i)
		keys[k] = true
		if pb.WaterClass(w.Class) == pb.WaterClass_WATER_SEA {
			continue
		}
		for _, ring := range w.Rings {
			for a := range ring {
				p, q := ring[a], ring[(a+1)%len(ring)]
				onGrid := func(v float64) bool { return math.Abs(v/cm-math.Round(v/cm)) < 1e-3 }
				if (onGrid(p.X) && onGrid(q.X)) || (onGrid(p.Y) && onGrid(q.Y)) {
					continue
				}
				l := p.Dist(q)
				for s := 0.0; s < l; s += 8 {
					z := ground(p.Add(q.Sub(p).Mul(s / l)))
					if z >= -1 {
						samples[k] = append(samples[k], z)
					}
				}
			}
		}
	}
	out := map[string]float64{}
	for k := range keys {
		s := samples[k]
		if len(s) == 0 {
			out[k] = 0
			continue
		}
		sort.Float64s(s)
		out[k] = s[len(s)/4]
	}
	return out
}

// waterIndex answers "which water level is at p".
// LoadTerrain reads terrain.bin (nil without elevation).
func (e *Env) LoadTerrain() (*TerrainGrid, *ElevationReport, error) {
	f, err := os.Open(e.W("terrain.bin"))
	if os.IsNotExist(err) || len(e.C.City.ElevationSources) == 0 {
		return nil, nil, nil
	}
	if err != nil {
		return nil, nil, err
	}
	defer f.Close()
	var t TerrainGrid
	if err := gob.NewDecoder(f).Decode(&t); err != nil {
		return nil, nil, err
	}
	var rep ElevationReport
	if err := readJSON(e.W("elevation.json"), &rep); err != nil {
		return nil, nil, err
	}
	return &t, &rep, nil
}
