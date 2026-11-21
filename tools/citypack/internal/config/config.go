// Package config loads city.yaml, tuning.yaml, landmarks.yaml and spots.yaml.
package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

type LatLon struct {
	Lat float64 `yaml:"lat"`
	Lon float64 `yaml:"lon"`
}

type City struct {
	ID              string       `yaml:"id"`
	Name            string       `yaml:"name"`
	Origin          LatLon       `yaml:"origin"`
	DriveSide       string       `yaml:"drive_side"`
	Units           string       `yaml:"units"`
	Area            string       `yaml:"area"`
	OvertureRelease string       `yaml:"overture_release"`
	HeightSources   []string     `yaml:"height_sources"`
	RoadKeepClasses []string     `yaml:"road_keep_classes"`
	RoadKeepNames   []string     `yaml:"road_keep_names"`
	Style           string       `yaml:"style"`
	Start           Start        `yaml:"start"`
	DefaultHeightM  float64      `yaml:"default_height_m"`
	MaxChunkKB      int          `yaml:"max_chunk_kb"`
	DistrictsFile   string       `yaml:"districts"`
	Dir             string       `yaml:"-"`
	AreaRing        [][2]float64 `yaml:"-"` // lon, lat
}

type Start struct {
	LatLon     `yaml:",inline"`
	HeadingDeg float64 `yaml:"heading_deg"` // compass: 0 = north, 90 = east
	Street     string  `yaml:"street"`      // snap only onto edges with this name
}

// Tuning is the part of content/tuning.yaml the pipeline uses. Every field is required.
type Tuning struct {
	CarScale       float64 `yaml:"car_scale"`
	LaneWidthM     float64 `yaml:"lane_width_m"`
	SidewalkWidthM float64 `yaml:"sidewalk_width_m"`
	ChunkM         int     `yaml:"chunk_m"`
	Roads          struct {
		LanesByClass        map[string]int `yaml:"lanes_by_class"`
		LinkLanes           int            `yaml:"link_lanes"`
		MinKeptLanes        int            `yaml:"min_kept_lanes"`
		OnewayLaneReduction int            `yaml:"oneway_lane_reduction"`
		AlleyWidthLanes     float64        `yaml:"alley_width_lanes"`
	} `yaml:"roads"`
	Buildings struct {
		SimplifyM       float64   `yaml:"simplify_m"`
		MergeGapM       float64   `yaml:"merge_gap_m"`
		HeightBandsM    []float64 `yaml:"height_bands_m"`
		MinAreaM2       float64   `yaml:"min_area_m2"`
		FloorHeightM    float64   `yaml:"floor_height_m"`
		LandmarkSearchM float64   `yaml:"landmark_search_m"`
		DegenerateM2    float64   `yaml:"degenerate_m2"`
	} `yaml:"buildings"`
	Ground struct {
		SimplifyM float64 `yaml:"simplify_m"`
		MinAreaM2 float64 `yaml:"min_area_m2"`
	} `yaml:"ground"`
}

func (t *Tuning) check() error {
	b, g, r := t.Buildings, t.Ground, t.Roads
	for name, v := range map[string]float64{
		"car_scale": t.CarScale, "lane_width_m": t.LaneWidthM, "sidewalk_width_m": t.SidewalkWidthM,
		"chunk_m": float64(t.ChunkM), "roads.link_lanes": float64(r.LinkLanes), "roads.min_kept_lanes": float64(r.MinKeptLanes),
		"roads.alley_width_lanes": r.AlleyWidthLanes, "buildings.simplify_m": b.SimplifyM,
		"buildings.merge_gap_m": b.MergeGapM, "buildings.min_area_m2": b.MinAreaM2,
		"buildings.floor_height_m": b.FloorHeightM, "buildings.landmark_search_m": b.LandmarkSearchM,
		"buildings.degenerate_m2": b.DegenerateM2, "ground.simplify_m": g.SimplifyM, "ground.min_area_m2": g.MinAreaM2,
	} {
		if v <= 0 {
			return fmt.Errorf("tuning.yaml: %s missing or not positive", name)
		}
	}
	if len(r.LanesByClass) == 0 || len(b.HeightBandsM) == 0 {
		return fmt.Errorf("tuning.yaml: roads.lanes_by_class and buildings.height_bands_m are required")
	}
	return nil
}

type Landmark struct {
	ID         string  `yaml:"id"`
	Name       string  `yaml:"name"`
	Lat        float64 `yaml:"lat"`
	Lon        float64 `yaml:"lon"`
	OvertureID string  `yaml:"overture_id"`
	HeightM    float64 `yaml:"height_m"`
	Hero       bool    `yaml:"hero"`
	Blurb      string  `yaml:"blurb"`
	// Kind "plaza" marks an open space (Times Square) with no building to match.
	Kind string `yaml:"kind"`
}

type Spot struct {
	ID   string  `yaml:"id"`
	Kind string  `yaml:"kind"`
	Name string  `yaml:"name"`
	Lat  float64 `yaml:"lat"`
	Lon  float64 `yaml:"lon"`
}

// Content is everything citypack reads for one city.
type Content struct {
	City      City
	Tuning    Tuning
	Landmarks []Landmark
	Spots     []Spot
}

func Load(contentDir, cityID string) (*Content, error) {
	dir := filepath.Join(contentDir, "cities", cityID)
	c := &Content{}
	if err := readYAML(filepath.Join(dir, "city.yaml"), &c.City); err != nil {
		return nil, err
	}
	c.City.Dir = dir
	if c.City.ID != cityID {
		return nil, fmt.Errorf("city.yaml id %q != %q", c.City.ID, cityID)
	}
	if c.City.OvertureRelease == "" {
		return nil, fmt.Errorf("city.yaml: overture_release must be pinned")
	}
	if c.City.DefaultHeightM == 0 {
		c.City.DefaultHeightM = 12
	}
	if c.City.MaxChunkKB == 0 {
		c.City.MaxChunkKB = 512
	}
	if err := readYAML(filepath.Join(contentDir, "tuning.yaml"), &c.Tuning); err != nil {
		return nil, err
	}
	if err := c.Tuning.check(); err != nil {
		return nil, err
	}
	var lm struct {
		Landmarks []Landmark `yaml:"landmarks"`
	}
	if err := readYAMLOptional(filepath.Join(dir, "landmarks.yaml"), &lm); err != nil {
		return nil, err
	}
	c.Landmarks = lm.Landmarks
	var sp struct {
		Spots []Spot `yaml:"spots"`
	}
	if err := readYAMLOptional(filepath.Join(dir, "spots.yaml"), &sp); err != nil {
		return nil, err
	}
	c.Spots = sp.Spots
	ring, err := readAreaRing(filepath.Join(dir, c.City.Area))
	if err != nil {
		return nil, err
	}
	c.City.AreaRing = ring
	return c, nil
}

func readYAML(path string, v any) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if err := readYAMLBytes(b, v); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	return nil
}

func readYAMLBytes(b []byte, v any) error { return yaml.Unmarshal(b, v) }

func readYAMLOptional(path string, v any) error {
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return nil
	}
	return readYAML(path, v)
}

// readAreaRing returns the outer ring of the first polygon in a GeoJSON FeatureCollection.
func readAreaRing(path string) ([][2]float64, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var fc struct {
		Features []struct {
			Geometry struct {
				Type        string         `json:"type"`
				Coordinates [][][2]float64 `json:"coordinates"`
			} `json:"geometry"`
		} `json:"features"`
	}
	if err := json.Unmarshal(b, &fc); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	if len(fc.Features) == 0 || fc.Features[0].Geometry.Type != "Polygon" {
		return nil, fmt.Errorf("%s: expected a Polygon feature", path)
	}
	return fc.Features[0].Geometry.Coordinates[0], nil
}

// BBox of the area ring: minLon, minLat, maxLon, maxLat.
func (c *City) BBox() (float64, float64, float64, float64) {
	x1, y1, x2, y2 := 180.0, 90.0, -180.0, -90.0
	for _, p := range c.AreaRing {
		x1, x2 = min(x1, p[0]), max(x2, p[0])
		y1, y2 = min(y1, p[1]), max(y2, p[1])
	}
	return x1, y1, x2, y2
}

// AreaWKT is the area polygon in WGS84 as WKT.
func (c *City) AreaWKT() string {
	s := "POLYGON(("
	for i, p := range c.AreaRing {
		if i > 0 {
			s += ","
		}
		s += fmt.Sprintf("%.7f %.7f", p[0], p[1])
	}
	return s + "))"
}

// ProjString is the PROJ definition of the local equirectangular projection.
func (c *City) ProjString() string {
	return fmt.Sprintf("+proj=eqc +lat_ts=%.7f +lat_0=%.7f +lon_0=%.7f +R=6371008.8 +units=m +no_defs",
		c.Origin.Lat, c.Origin.Lat, c.Origin.Lon)
}
