package dem

import (
	"bufio"
	"fmt"
	"log/slog"
	"math"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// Sampler returns the elevation in metres at a WGS84 point; ok is false outside the coverage or
// on a no-data cell.
type Sampler interface {
	At(lon, lat float64) (z float64, ok bool)
	Name() string
	// Lidar reports bare-earth data at metre resolution (profile smoothing window `lidar`),
	// false for coarse global data (window `coarse`).
	Lidar() bool
}

// tileSampler samples a terrarium tile mosaic in Web Mercator pixel space.
type tileSampler struct {
	g      *Grid
	r      TileRange
	ox, oy float64
	name   string
	lidar  bool
}

func (s *tileSampler) Name() string { return s.name }
func (s *tileSampler) Lidar() bool  { return s.lidar }

func (s *tileSampler) At(lon, lat float64) (float64, bool) {
	// Pixel centres sit at integer + 0.5 in the global pixel grid.
	x := LonToPixelX(lon, s.r.Z) - s.ox - 0.5
	y := LatToPixelY(lat, s.r.Z) - s.oy - 0.5
	if x < -1 || y < -1 || x > float64(s.g.W) || y > float64(s.g.H) {
		return 0, false
	}
	z := s.g.Bilinear(x, y)
	if math.IsNaN(z) {
		return 0, false
	}
	return z, true
}

// TerrainTiles fetches (or reads from cacheDir) every terrarium tile covering b at zoom z and
// returns a sampler over their mosaic.
func TerrainTiles(b BBox, z int, cacheDir string) (Sampler, error) {
	r := TilesFor(b, z)
	f := NewFetcher(DefaultTileURL, cacheDir, 8, 4)
	tiles, err := f.GetRange(r, nil)
	if err != nil {
		return nil, err
	}
	slog.Info("dem: terrain tiles", "zoom", z, "tiles", len(tiles), "cached", f.hits.Load(), "downloaded", f.misses.Load())
	g, err := Mosaic(tiles, r)
	if err != nil {
		return nil, err
	}
	return &tileSampler{g: g, r: r, ox: float64(r.X0 * TileSize), oy: float64(r.Y0 * TileSize), name: "terrain_tiles"}, nil
}

// GSITiles reads the GSI elevation tiles DEM5A (Japan: 5 m laser, bare earth) at zoom z (≤ 15).
// Water and tiles out at sea have no data (At reports !ok, the elevation step fills them).
func GSITiles(b BBox, z int, cacheDir string) (Sampler, error) {
	z = min(z, 15)
	r := TilesFor(b, z)
	f := NewFetcher(GSITileURL, cacheDir, 4, 4)
	f.missingOK = true
	tiles, err := f.GetRange(r, nil)
	if err != nil {
		return nil, err
	}
	slog.Info("dem: gsi tiles", "zoom", z, "tiles", len(tiles), "cached", f.hits.Load(), "downloaded", f.misses.Load())
	g, err := mosaic(tiles, r, DecodeGSI)
	if err != nil {
		return nil, err
	}
	return &tileSampler{g: g, r: r, ox: float64(r.X0 * TileSize), oy: float64(r.Y0 * TileSize), name: "gsi_tiles", lidar: true}, nil
}

// ascSampler is an ESRI ASCII grid in WGS84 degrees (gdalwarp -t_srs EPSG:4326 -of AAIGrid).
type ascSampler struct {
	g              *Grid
	x0, yTop, cell float64
	nodata         float32
	name           string
}

func (s *ascSampler) Name() string { return "local:" + s.name }
func (s *ascSampler) Lidar() bool  { return true }

func (s *ascSampler) At(lon, lat float64) (float64, bool) {
	x := (lon-s.x0)/s.cell - 0.5
	y := (s.yTop-lat)/s.cell - 0.5
	if x < 0 || y < 0 || x > float64(s.g.W-1) || y > float64(s.g.H-1) {
		return 0, false
	}
	ix, iy := int(x), int(y)
	for _, d := range [][2]int{{0, 0}, {1, 0}, {0, 1}, {1, 1}} {
		if v := s.g.ClampedAt(ix+d[0], iy+d[1]); v == s.nodata || math.IsNaN(float64(v)) {
			return 0, false
		}
	}
	return s.g.Bilinear(x, y), true
}

// LocalASC reads the first *.asc file in dir (content/cities/<id>/dem/, see its README.md).
// It returns nil without error when the directory has no grid.
func LocalASC(dir string) (Sampler, error) {
	files, _ := filepath.Glob(filepath.Join(dir, "*.asc"))
	if len(files) == 0 {
		return nil, nil
	}
	return ReadASC(files[0])
}

// ReadASC parses an ESRI ASCII grid (header keys ncols, nrows, xllcorner|xllcenter,
// yllcorner|yllcenter, cellsize, NODATA_value) whose coordinates are WGS84 degrees.
func ReadASC(path string) (Sampler, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<30)
	sc.Split(bufio.ScanWords)
	hdr := map[string]float64{}
	var first string
	for sc.Scan() {
		w := sc.Text()
		if _, err := strconv.ParseFloat(w, 64); err == nil {
			first = w
			break
		}
		if !sc.Scan() {
			return nil, fmt.Errorf("%s: truncated header", path)
		}
		v, err := strconv.ParseFloat(sc.Text(), 64)
		if err != nil {
			return nil, fmt.Errorf("%s: header %s: %w", path, w, err)
		}
		hdr[strings.ToLower(w)] = v
	}
	w, h, cell := int(hdr["ncols"]), int(hdr["nrows"]), hdr["cellsize"]
	if w < 2 || h < 2 || cell <= 0 {
		return nil, fmt.Errorf("%s: bad header %v", path, hdr)
	}
	x0, y0 := hdr["xllcorner"], hdr["yllcorner"]
	if v, ok := hdr["xllcenter"]; ok {
		x0 = v - cell/2
	}
	if v, ok := hdr["yllcenter"]; ok {
		y0 = v - cell/2
	}
	nd, ok := hdr["nodata_value"]
	if !ok {
		nd = -9999
	}
	g := NewGrid(w, h)
	i := 0
	parse := func(s string) error {
		v, err := strconv.ParseFloat(s, 64)
		if err != nil {
			return fmt.Errorf("%s: value %d: %w", path, i, err)
		}
		if i < len(g.Data) {
			g.Data[i] = float32(v)
		}
		i++
		return nil
	}
	if err := parse(first); err != nil {
		return nil, err
	}
	for sc.Scan() {
		if err := parse(sc.Text()); err != nil {
			return nil, err
		}
	}
	if i != w*h {
		return nil, fmt.Errorf("%s: %d values, want %d", path, i, w*h)
	}
	return &ascSampler{g: g, x0: x0, yTop: y0 + float64(h)*cell, cell: cell, nodata: float32(nd), name: filepath.Base(path)}, nil
}
