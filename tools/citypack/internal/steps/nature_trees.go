package steps

import (
	"encoding/csv"
	"fmt"
	"hash/fnv"
	"io"
	"log/slog"
	"math"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strconv"
	"time"

	"citypack/internal/duck"
	"citypack/internal/geo"
	"citypack/internal/pb"
)

// Tree is one placed tree (nature_trees.json); X, Y in local metres.
type Tree struct {
	X, Y   float64
	Size   int // 0 S, 1 M, 2 L
	Jitter int // 0..63 colour jitter
	Src    string
}

// TreeReport is nature_trees.json.
type TreeReport struct {
	Trees  []Tree
	Counts map[string]int
}

// Trees places trees (specs/nature.md, plan ch. 4 step 4): the city inventory, then OSM tree
// points and rows, then a Poisson disk in green classes with a density; street trees go to the
// middle of the game sidewalk; no tree closer than its crown radius to a road corridor, building
// or water (street trees: their trunk stays off the carriageway and out of buildings); chunks
// over the limit are thinned evenly.
func (e *Env) Trees() error {
	nt := e.C.Tuning.Nature
	np := nt.Pipeline
	g, err := e.LoadGraph()
	if err != nil {
		return err
	}
	masses, err := e.LoadMasses()
	if err != nil {
		return err
	}
	water, err := e.LoadNaturePieces("nature_water.jsonl")
	if err != nil {
		return err
	}
	green, err := e.LoadNaturePieces("nature_green.jsonl")
	if err != nil {
		return err
	}
	ob := newObstacles(e, g, masses, water)
	area := e.AreaRingM()
	crown := func(size int) float64 { return nt.TreeSizes[[]string{"S", "M", "L"}[size]].CrownR }
	placed := newPointGrid(8)
	var trees []Tree
	counts := map[string]int{}
	// try places a tree from a point source: snapped to a sidewalk or kept as a park tree.
	try := func(p geo.Pt, size int, src string) {
		if !geo.PointInRing(p, area) {
			return
		}
		if q, ok := ob.sidewalk(p, np.StreetTreeSnapM); ok {
			switch {
			case ob.inBuilding(q, nt.TrunkRadiusM+0.5):
				counts[src+"_dropped_building"]++
				return
			case ob.inWater(q, nt.TrunkRadiusM):
				counts[src+"_dropped_water"]++
				return
			case ob.onCarriageway(q, nt.TrunkRadiusM+streetTrunkMargin):
				counts[src+"_dropped_carriageway"]++
				return
			case ob.underDeck(q, crown(size)+np.DeckTreeMarginM):
				counts[src+"_dropped_deck"]++
				return
			}
			if placed.near(q, np.TreeMinSpacingM) {
				counts[src+"_duplicate"]++
				return
			}
			placed.add(q)
			trees = append(trees, Tree{X: q.X, Y: q.Y, Size: size, Src: src})
			counts[src+"_street"]++
			return
		}
		r := crown(size)
		if ob.nearRoad(p, r) || ob.inBuilding(p, r) || ob.inWater(p, r) || ob.underDeck(p, r+np.DeckTreeMarginM) {
			counts[src+"_dropped_park"]++
			return
		}
		if placed.near(p, np.TreeMinSpacingM) {
			counts[src+"_duplicate"]++
			return
		}
		placed.add(p)
		trees = append(trees, Tree{X: p.X, Y: p.Y, Size: size, Src: src})
		counts[src+"_park"]++
	}

	// 1. City inventory.
	if inv := e.C.City.TreeInventory; inv != nil {
		pts, err := e.inventoryTrees()
		if err != nil {
			return err
		}
		for _, t := range pts {
			try(geo.Pt{X: t.X, Y: t.Y}, t.Size, "inventory")
		}
	}
	// 2. OSM tree points and rows (Overture base/land subtype tree).
	osm, err := e.osmTrees(np.TreeRowStepM)
	if err != nil {
		return err
	}
	for _, p := range osm {
		try(p, 1, "osm")
	}
	// 3. Poisson disk in green classes with a density, seeded per chunk.
	sort.SliceStable(green, func(i, j int) bool {
		if green[i].CY != green[j].CY {
			return green[i].CY < green[j].CY
		}
		return green[i].CX < green[j].CX
	})
	dens := map[pb.GreenClass]float64{
		pb.GreenClass_GREEN_WOOD: nt.TreesPerHa["wood"], pb.GreenClass_GREEN_PARKLAND: nt.TreesPerHa["parkland"],
		pb.GreenClass_GREEN_GARDEN: nt.TreesPerHa["garden"], pb.GreenClass_GREEN_CEMETERY: nt.TreesPerHa["cemetery"],
	}
	rngs := map[[2]int]*prng{}
	for _, piece := range green {
		d := dens[pb.GreenClass(piece.Class)]
		if d <= 0 {
			continue
		}
		k := [2]int{piece.CX, piece.CY}
		rng := rngs[k]
		if rng == nil {
			h := fnv.New32a()
			fmt.Fprintf(h, "%s/%d_%d", e.C.City.ID, piece.CX, piece.CY)
			rng = newPRNG(h.Sum32())
			rngs[k] = rng
		}
		a := math.Abs(geo.SignedArea(piece.Rings[0]))
		for _, hole := range piece.Rings[1:] {
			a -= math.Abs(geo.SignedArea(hole))
		}
		minX, minY, maxX, maxY := bounds(piece.Rings[0])
		in := func(p geo.Pt) bool { return geo.PointInRing(p, piece.Rings[0]) && !inAnyRing(p, piece.Rings[1:]) }
		have := 0
		for _, q := range placed.within(minX, minY, maxX, maxY) {
			if in(q) {
				have++
			}
		}
		want := int(math.Round(a/1e4*d)) - have
		spacing := 0.75 * math.Sqrt(1e4/d)
		for tries := 0; want > 0 && tries < 30*int(math.Round(a/1e4*d)+1); tries++ {
			u := rng.float()
			size := 0
			if u >= np.TreeSizeMix[0] {
				size = 1
			}
			if u >= np.TreeSizeMix[0]+np.TreeSizeMix[1] {
				size = 2
			}
			p := geo.Pt{X: minX + rng.float()*(maxX-minX), Y: minY + rng.float()*(maxY-minY)}
			if !in(p) || placed.near(p, spacing) {
				continue
			}
			r := crown(size)
			if ob.nearRoad(p, r) || ob.inBuilding(p, r) || ob.inWater(p, r) || ob.underDeck(p, r+np.DeckTreeMarginM) {
				continue
			}
			placed.add(p)
			trees = append(trees, Tree{X: p.X, Y: p.Y, Size: size, Src: "poisson"})
			counts["poisson"]++
			want--
		}
	}
	// 4. Chunk limit, colour jitter, deterministic order.
	cm := float64(e.C.Tuning.ChunkM)
	byChunk := map[[2]int][]Tree{}
	for _, t := range trees {
		k := [2]int{int(math.Floor(t.X / cm)), int(math.Floor(t.Y / cm))}
		byChunk[k] = append(byChunk[k], t)
	}
	var keys [][2]int
	for k := range byChunk {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i][1] != keys[j][1] {
			return keys[i][1] < keys[j][1]
		}
		return keys[i][0] < keys[j][0]
	})
	var out []Tree
	thinned := 0
	for _, k := range keys {
		ts := byChunk[k]
		sort.Slice(ts, func(i, j int) bool {
			if ts[i].X != ts[j].X {
				return ts[i].X < ts[j].X
			}
			return ts[i].Y < ts[j].Y
		})
		if n, lim := len(ts), nt.TreesPerChunkMax; n > lim {
			keep := make([]Tree, 0, lim)
			for i := 0; i < lim; i++ {
				keep = append(keep, ts[i*n/lim])
			}
			thinned += n - lim
			ts = keep
		}
		for i := range ts {
			h := fnv.New32a()
			fmt.Fprintf(h, "%d %d", geo.DM(ts[i].X), geo.DM(ts[i].Y))
			ts[i].Jitter = int(h.Sum32() % 64)
		}
		out = append(out, ts...)
	}
	counts["thinned"] = thinned
	counts["total"] = len(out)
	slog.Info("nature: trees", "total", len(out), "inventory_street", counts["inventory_street"], "inventory_park", counts["inventory_park"],
		"osm", counts["osm_street"]+counts["osm_park"], "poisson", counts["poisson"], "thinned", thinned)
	return writeJSON(e.W("nature_trees.json"), TreeReport{Trees: out, Counts: counts})
}

// LoadTrees reads nature_trees.json.
func (e *Env) LoadTrees() (TreeReport, error) {
	var r TreeReport
	return r, readJSON(e.W("nature_trees.json"), &r)
}

// inventoryTrees downloads (once, cached in trees/) and reads the city tree census.
func (e *Env) inventoryTrees() ([]Tree, error) {
	inv := e.C.City.TreeInventory
	dir := e.W("trees")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	path := dir + "/inventory.csv"
	if _, err := os.Stat(path); err != nil || e.Refetch {
		x1, y1, x2, y2 := e.C.City.BBox()
		where := fmt.Sprintf("%s between %.6f and %.6f AND %s between %.6f and %.6f", inv.Lat, y1, y2, inv.Lon, x1, x2)
		if inv.Where != "" {
			where = inv.Where + " AND " + where
		}
		q := url.Values{}
		q.Set("$select", inv.DBH+","+inv.Lat+","+inv.Lon)
		q.Set("$where", where)
		q.Set("$limit", "500000")
		client := &http.Client{Timeout: 10 * time.Minute}
		resp, err := client.Get(inv.URL + "?" + q.Encode())
		if err != nil {
			return nil, err
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("tree inventory: %s", resp.Status)
		}
		f, err := os.Create(path + ".tmp")
		if err != nil {
			return nil, err
		}
		if _, err := io.Copy(f, resp.Body); err != nil {
			f.Close()
			return nil, err
		}
		if err := f.Close(); err != nil {
			return nil, err
		}
		if err := os.Rename(path+".tmp", path); err != nil {
			return nil, err
		}
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	recs, err := csv.NewReader(f).ReadAll()
	if err != nil {
		return nil, err
	}
	var out []Tree
	for i, r := range recs {
		if i == 0 || len(r) < 3 {
			continue
		}
		dbh, err1 := strconv.ParseFloat(r[0], 64)
		lat, err2 := strconv.ParseFloat(r[1], 64)
		lon, err3 := strconv.ParseFloat(r[2], 64)
		if err1 != nil || err2 != nil || err3 != nil {
			continue
		}
		cmDBH := dbh * inv.DBHToCM
		size := 2
		switch {
		case cmDBH < 20:
			size = 0
		case cmDBH < 50:
			size = 1
		}
		p := e.Proj.Forward(lon, lat)
		out = append(out, Tree{X: p.X, Y: p.Y, Size: size})
	}
	slog.Info("nature: tree inventory", "rows", len(out))
	return out, nil
}

// osmTrees returns OSM tree points and tree rows sampled every step metres.
func (e *Env) osmTrees(step float64) ([]geo.Pt, error) {
	rows, err := duck.Query("osm trees", "", fmt.Sprintf(
		`SELECT ST_AsText(%s) FROM read_parquet(%s) WHERE subtype = 'tree' AND ST_GeometryType(geometry) IN ('POINT', 'LINESTRING') ORDER BY 1`,
		e.projSQL("geometry"), duck.Quote(e.Raw("land"))))
	if err != nil {
		return nil, err
	}
	var out []geo.Pt
	for _, r := range rows {
		pts := parseWKTPoints(r[0])
		if len(pts) == 1 {
			out = append(out, pts[0])
			continue
		}
		total := geo.PolylineLength(pts)
		for s := 0.0; s <= total; s += step {
			p, _ := along(pts, s)
			out = append(out, p)
		}
	}
	return out, nil
}

// parseWKTPoints reads the coordinates of a POINT or LINESTRING WKT.
func parseWKTPoints(w string) []geo.Pt {
	var out []geo.Pt
	start := -1
	for i, c := range w {
		if c == '(' {
			start = i + 1
		}
	}
	if start < 0 {
		return nil
	}
	end := len(w)
	for end > 0 && w[end-1] == ')' {
		end--
	}
	for _, part := range splitComma(w[start:end]) {
		var x, y float64
		if _, err := fmt.Sscanf(part, "%g %g", &x, &y); err == nil {
			out = append(out, geo.Pt{X: x, Y: y})
		}
	}
	return out
}

func splitComma(s string) []string {
	var out []string
	cur := ""
	for _, c := range s {
		if c == ',' {
			out = append(out, cur)
			cur = ""
			continue
		}
		cur += string(c)
	}
	return append(out, cur)
}

func bounds(r []geo.Pt) (minX, minY, maxX, maxY float64) {
	minX, minY, maxX, maxY = math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)
	for _, p := range r {
		minX, maxX = math.Min(minX, p.X), math.Max(maxX, p.X)
		minY, maxY = math.Min(minY, p.Y), math.Max(maxY, p.Y)
	}
	return
}

// prng is the shared xorshift32 of specs/prng.md.
type prng struct{ x uint32 }

func newPRNG(seed uint32) *prng {
	if seed == 0 {
		seed = 0x9E3779B9
	}
	return &prng{seed}
}

func (r *prng) next() uint32 {
	r.x ^= r.x << 13
	r.x ^= r.x >> 17
	r.x ^= r.x << 5
	return r.x
}

func (r *prng) float() float64 { return float64(r.next()) / 4294967296.0 }
