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
	ID              string   `yaml:"id"`
	Name            string   `yaml:"name"`
	Origin          LatLon   `yaml:"origin"`
	DriveSide       string   `yaml:"drive_side"`
	Units           string   `yaml:"units"`
	Area            string   `yaml:"area"`
	OvertureRelease string   `yaml:"overture_release"`
	HeightSources   []string `yaml:"height_sources"`
	RoadKeepClasses []string `yaml:"road_keep_classes"`
	RoadKeepNames   []string `yaml:"road_keep_names"`
	NameLangs       []string `yaml:"name_langs"` // e.g. [en, ja-Latn]: Overture names.common first, Latin-script primary last
	Style           string   `yaml:"style"`
	Start           Start    `yaml:"start"`
	DefaultHeightM  float64  `yaml:"default_height_m"`
	MaxChunkKB      int      `yaml:"max_chunk_kb"`
	DistrictsFile   string   `yaml:"districts"`
	// Terrain (specs/terrain.md): sources in order of preference; `local` reads
	// content/cities/<id>/dem/*.asc, `terrain_tiles` AWS Terrain Tiles. Empty = no elevation.
	ElevationSources     []string `yaml:"elevation_sources"`
	ElevationIsBareEarth *bool    `yaml:"elevation_is_bare_earth"`
	// Nature (specs/nature.md).
	TreeInventory    *TreeInventory     `yaml:"tree_inventory"`
	WaterClassByName map[string]string  `yaml:"water_class_by_name"`
	WaterLevelM      map[string]float64 `yaml:"water_level_m"` // real water level by name, over the bank estimate (tidal rivers in a surface model)
	Dir              string             `yaml:"-"`
	AreaRing         [][2]float64       `yaml:"-"` // lon, lat
}

// TreeInventory is a city tree census read as CSV (specs/nature.md, trees step 1).
type TreeInventory struct {
	URL         string  `yaml:"url"` // Socrata-style CSV endpoint; the area bbox is appended to $where
	Where       string  `yaml:"where"`
	Lat         string  `yaml:"lat"`
	Lon         string  `yaml:"lon"`
	DBH         string  `yaml:"dbh"`       // trunk diameter column
	DBHToCM     float64 `yaml:"dbh_to_cm"` // unit factor (inches: 2.54)
	Attribution string  `yaml:"attribution"`
	Licence     string  `yaml:"licence"`
}

// BareEarth reports whether the DEM is a terrain model (default) rather than a surface model.
func (c *City) BareEarth() bool { return c.ElevationIsBareEarth == nil || *c.ElevationIsBareEarth }

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
	Zones struct {
		StreetWidthM float64 `yaml:"street_width_m"`
		GapMarginM   float64 `yaml:"gap_margin_m"`
		MinBarrierM  float64 `yaml:"min_barrier_m"`
	} `yaml:"zones"`
	Trams struct {
		MinTrackM     float64 `yaml:"min_track_m"`
		StopSpacingM  float64 `yaml:"stop_spacing_m"`
		StopMinChainM float64 `yaml:"stop_min_chain_m"`
	} `yaml:"trams"`
	Terrain TerrainTuning `yaml:"terrain"`
	Nature  NatureTuning  `yaml:"nature"`
	Flow    struct {
		GapCloseM float64 `yaml:"gap_close_m"`
	} `yaml:"flow"`
	Models ModelsTuning `yaml:"models"`
}

// ModelsTuning is tuning.yaml `models` (specs/models.md).
type ModelsTuning struct {
	Enabled          bool    `yaml:"enabled"`
	MaxTris          int     `yaml:"max_tris"`
	MaxTrisException int     `yaml:"max_tris_exception"`
	CityMaxTris      int     `yaml:"city_max_tris"`
	CityMaxBytes     int     `yaml:"city_max_bytes"`
	MinDetailM       float64 `yaml:"min_detail_m"`
	MaxDetailM       float64 `yaml:"max_detail_m"`
	DetailStepM      float64 `yaml:"detail_step_m"`
	NearM            float64 `yaml:"near_m"`
	HysteresisM      float64 `yaml:"hysteresis_m"`
	MaxFull          int     `yaml:"max_full"`
	RoofPlanMaxPolys int     `yaml:"roof_plan_max_polys"`
	WeldM            float64 `yaml:"weld_m"`
	PlanSimplifyM    float64 `yaml:"plan_simplify_m"`
	ReplaceShare     float64 `yaml:"replace_share"`
	FootTolM         float64 `yaml:"foot_tolerance_m"`
	MaxOffsetM       float64 `yaml:"max_offset_m"`
	CopperMinTopM    float64 `yaml:"copper_min_top_m"` // v2: slender tall parts get copper roofs
	CopperSlender    float64 `yaml:"copper_slender"`
	BridgeEndM       float64 `yaml:"bridge_end_m"`     // v3: deck this close to either end sits on the terrain
	BridgeClearM     float64 `yaml:"bridge_clear_m"`   // v3 validate: no bridge face from a road up to this
	BridgeBelowM     float64 `yaml:"bridge_below_m"`   // v3 validate: … nor this close below it (depth fight)
	GroundFloatM     float64 `yaml:"ground_float_m"`   // v4: ground this high above the lowest is an underside
	PartBoxSlackM    float64 `yaml:"part_box_slack_m"` // v4: models.yaml `parts` box slack for other groups
}

// ModelsFile is content/cities/<id>/models.yaml (specs/models.md, METROPOLE_LANDMARKS3D_PLAN 4.3).
type ModelsFile struct {
	Source string                 `yaml:"source"` // ipr_praha_3d | nyc_3d | plateau | overture_parts | manual
	Files  []string               `yaml:"files"`  // source files in run/citypack/<id>/raw/models/
	Models map[string]ModelConfig `yaml:"models"`
}

type ModelConfig struct {
	Select struct {
		BufferM float64      `yaml:"buffer_m"`
		Area    [][2]float64 `yaml:"area"` // lon, lat ring: the landmark's grounds beyond its own building
	} `yaml:"select"`
	Include []string          `yaml:"include"`
	Exclude []string          `yaml:"exclude"`
	MaxTris int               `yaml:"max_tris"`
	Roles   map[string]string `yaml:"roles"`  // source building or part id → role of its roofs
	Walls   map[string]string `yaml:"walls"`  // v2: source building or part id → role of its walls
	Towers  map[string]string `yaml:"towers"` // v3: source building id → role of its tower roofs (instead of copper)
	Bridges struct {
		File string  `yaml:"file"` // v3: IPR "Mosty 3D" shapefile (polygonZ) in raw/models/
		IDs  []int64 `yaml:"ids"`  // ID_BUD of the bridges in the model
	} `yaml:"bridges"`
	Manual string `yaml:"manual"`
	// v4: role overrides of one part of a source building (IPR parts have no gml:id): the part
	// whose footprint box is the smallest one containing `at` (lon, lat).
	Parts []PartRole `yaml:"parts"`
}

// PartRole is one models.yaml `parts` entry (specs/models.md v4). XY is `at` in local metres,
// filled by the models step.
type PartRole struct {
	At    [2]float64 `yaml:"at"`
	Walls string     `yaml:"walls"`
	Roof  string     `yaml:"roof"`
	XY    [2]float64 `yaml:"-"`
}

// TerrainTuning is tuning.yaml `terrain` (specs/terrain.md).
type TerrainTuning struct {
	Exaggeration float64            `yaml:"exaggeration"`
	GridM        float64            `yaml:"grid_m"`
	BlendM       float64            `yaml:"blend_m"`
	MaxGrade     map[string]float64 `yaml:"max_grade"`
	Bridge       struct {
		ClearWaterM float64 `yaml:"clear_water_m"`
		ClearRoadM  float64 `yaml:"clear_road_m"`
		MaxGrade    float64 `yaml:"max_grade"`
	} `yaml:"bridge"`
	Tunnel struct {
		DepthWaterM float64 `yaml:"depth_water_m"`
		DepthLandM  float64 `yaml:"depth_land_m"`
		MaxGrade    float64 `yaml:"max_grade"`
	} `yaml:"tunnel"`
	Pipeline struct {
		DemMarginM        float64 `yaml:"dem_margin_m"`
		DemGridM          float64 `yaml:"dem_grid_m"`
		DemZoom           int     `yaml:"dem_zoom"`
		CleanSigmaM       float64 `yaml:"clean_sigma_m"`
		CleanSigmaCoarseM float64 `yaml:"clean_sigma_coarse_m"`
		ProfileStepM      float64 `yaml:"profile_step_m"`
		ProfileWindowM    struct {
			Lidar  float64 `yaml:"lidar"`
			Coarse float64 `yaml:"coarse"`
		} `yaml:"profile_window_m"`
		ElevatedM         float64 `yaml:"elevated_m"`
		UnderwaterM       float64 `yaml:"underwater_m"`
		GradeTolM         float64 `yaml:"grade_tolerance_m"`
		GradePasses       int     `yaml:"grade_passes"`
		ZTolM             float64 `yaml:"z_tolerance_m"`
		RoadGapMaxM       float64 `yaml:"road_gap_max_m"`
		RoadGapShare      float64 `yaml:"road_gap_share"`
		BridgeMinClearM   float64 `yaml:"bridge_min_clear_m"`
		BridgeOverWaterM  float64 `yaml:"bridge_over_water_m"`
		ShadeStrength     float64 `yaml:"shade_strength"`
		ProfileFairPasses int     `yaml:"profile_fair_passes"`
		ElevatedFlag      struct {
			AboveM float64 `yaml:"above_m"`
			RunM   float64 `yaml:"run_m"`
		} `yaml:"elevated_flag"`
		Trench struct {
			MarginM float64 `yaml:"margin_m"`
			MaxM    float64 `yaml:"max_m"`
			Share   float64 `yaml:"share"`
		} `yaml:"trench"`
		RoadStrip struct {
			TolM  float64 `yaml:"tol_m"`
			Share float64 `yaml:"share"`
			MaxM  float64 `yaml:"max_m"`
		} `yaml:"road_strip"`
		ConformFit struct {
			StepM  float64 `yaml:"step_m"`
			Passes int     `yaml:"passes"`
		} `yaml:"conform_fit"`
		Sun struct {
			AzimuthDeg  float64 `yaml:"azimuth_deg"`
			AltitudeDeg float64 `yaml:"altitude_deg"`
		} `yaml:"sun"`
	} `yaml:"pipeline"`
	Lod struct {
		GridM           float64 `yaml:"grid_m"`
		Chunks          int     `yaml:"chunks"`
		BlockMergeM     float64 `yaml:"block_merge_m"`
		SimplifyM       float64 `yaml:"simplify_m"`
		ParklandHeightM float64 `yaml:"parkland_height_m"`
	} `yaml:"lod"`
}

// TreeSize is one entry of nature.tree_sizes.
type TreeSize struct {
	CrownR float64 `yaml:"crown_r"`
	Height float64 `yaml:"height"`
}

// NatureTuning is tuning.yaml `nature` (specs/nature.md).
type NatureTuning struct {
	TreeSizes        map[string]TreeSize `yaml:"tree_sizes"`
	TreesPerHa       map[string]float64  `yaml:"trees_per_ha"`
	TreesPerChunkMax int                 `yaml:"trees_per_chunk_max"`
	Wood             struct {
		CanopyHeightM float64 `yaml:"canopy_height_m"`
	} `yaml:"wood"`
	ShoreBandM   float64 `yaml:"shore_band_m"`
	TrunkRadiusM float64 `yaml:"trunk_radius_m"`
	Pipeline     struct {
		SimplifyM        float64   `yaml:"simplify_m"`
		SmallWaterM2     float64   `yaml:"small_water_m2"`
		StreamRiverM     float64   `yaml:"stream_river_m"`
		WaterNameSearchM float64   `yaml:"water_name_search_m"`
		LabelWaterHa     float64   `yaml:"label_water_ha"`
		LabelGreenHa     float64   `yaml:"label_green_ha"`
		NamedWaterHa     float64   `yaml:"named_water_ha"`
		AreaNameWaterM   float64   `yaml:"area_name_water_m"`
		AreaNameParkM    float64   `yaml:"area_name_park_m"`
		BigParkHa        float64   `yaml:"big_park_ha"`
		WoodCoverHa      float64   `yaml:"wood_cover_ha"`
		TreeSizeMix      []float64 `yaml:"tree_size_mix"`
		StreetTreeSnapM  float64   `yaml:"street_tree_snap_m"`
		TreeMinSpacingM  float64   `yaml:"tree_min_spacing_m"`
		TreeRowStepM     float64   `yaml:"tree_row_step_m"`
		DeckTreeMarginM  float64   `yaml:"deck_tree_margin_m"`
	} `yaml:"pipeline"`
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
		"zones.street_width_m": t.Zones.StreetWidthM, "zones.gap_margin_m": t.Zones.GapMarginM, "zones.min_barrier_m": t.Zones.MinBarrierM,
		"trams.min_track_m": t.Trams.MinTrackM, "trams.stop_spacing_m": t.Trams.StopSpacingM, "trams.stop_min_chain_m": t.Trams.StopMinChainM,
	} {
		if v <= 0 {
			return fmt.Errorf("tuning.yaml: %s missing or not positive", name)
		}
	}
	tt, tp, nt, np := t.Terrain, t.Terrain.Pipeline, t.Nature, t.Nature.Pipeline
	for name, v := range map[string]float64{
		"terrain.exaggeration": tt.Exaggeration, "terrain.grid_m": tt.GridM, "terrain.blend_m": tt.BlendM,
		"terrain.bridge.clear_water_m": tt.Bridge.ClearWaterM, "terrain.bridge.clear_road_m": tt.Bridge.ClearRoadM,
		"terrain.bridge.max_grade": tt.Bridge.MaxGrade, "terrain.tunnel.depth_water_m": tt.Tunnel.DepthWaterM,
		"terrain.tunnel.depth_land_m": tt.Tunnel.DepthLandM, "terrain.tunnel.max_grade": tt.Tunnel.MaxGrade,
		"terrain.pipeline.dem_margin_m": tp.DemMarginM, "terrain.pipeline.dem_grid_m": tp.DemGridM,
		"terrain.pipeline.dem_zoom": float64(tp.DemZoom), "terrain.pipeline.clean_sigma_m": tp.CleanSigmaM, "terrain.pipeline.clean_sigma_coarse_m": tp.CleanSigmaCoarseM,
		"terrain.pipeline.profile_step_m": tp.ProfileStepM, "terrain.pipeline.profile_window_m.lidar": tp.ProfileWindowM.Lidar,
		"terrain.pipeline.profile_window_m.coarse": tp.ProfileWindowM.Coarse, "terrain.pipeline.elevated_m": tp.ElevatedM,
		"terrain.pipeline.underwater_m": tp.UnderwaterM, "terrain.pipeline.grade_tolerance_m": tp.GradeTolM,
		"terrain.pipeline.grade_passes": float64(tp.GradePasses), "terrain.pipeline.z_tolerance_m": tp.ZTolM,
		"terrain.pipeline.road_gap_max_m": tp.RoadGapMaxM, "terrain.pipeline.road_gap_share": tp.RoadGapShare,
		"terrain.pipeline.bridge_min_clear_m": tp.BridgeMinClearM, "terrain.pipeline.bridge_over_water_m": tp.BridgeOverWaterM,
		"terrain.pipeline.shade_strength": tp.ShadeStrength, "terrain.pipeline.profile_fair_passes": float64(tp.ProfileFairPasses), "terrain.pipeline.conform_fit.step_m": tp.ConformFit.StepM,
		"terrain.pipeline.road_strip.tol_m": tp.RoadStrip.TolM, "terrain.pipeline.road_strip.share": tp.RoadStrip.Share,
		"terrain.pipeline.road_strip.max_m":      tp.RoadStrip.MaxM,
		"terrain.pipeline.elevated_flag.above_m": tp.ElevatedFlag.AboveM, "terrain.pipeline.elevated_flag.run_m": tp.ElevatedFlag.RunM,
		"terrain.pipeline.trench.margin_m": tp.Trench.MarginM, "terrain.pipeline.trench.max_m": tp.Trench.MaxM, "terrain.pipeline.trench.share": tp.Trench.Share,
		"terrain.pipeline.conform_fit.passes": float64(tp.ConformFit.Passes), "terrain.pipeline.sun.altitude_deg": tp.Sun.AltitudeDeg,
		"terrain.lod.grid_m": tt.Lod.GridM, "terrain.lod.chunks": float64(tt.Lod.Chunks), "terrain.lod.block_merge_m": tt.Lod.BlockMergeM,
		"terrain.lod.simplify_m": tt.Lod.SimplifyM, "terrain.lod.parkland_height_m": tt.Lod.ParklandHeightM,
		"nature.trees_per_chunk_max": float64(nt.TreesPerChunkMax), "nature.wood.canopy_height_m": nt.Wood.CanopyHeightM,
		"nature.shore_band_m": nt.ShoreBandM, "nature.trunk_radius_m": nt.TrunkRadiusM,
		"nature.pipeline.simplify_m": np.SimplifyM, "nature.pipeline.small_water_m2": np.SmallWaterM2,
		"nature.pipeline.stream_river_m": np.StreamRiverM, "nature.pipeline.water_name_search_m": np.WaterNameSearchM,
		"nature.pipeline.label_water_ha": np.LabelWaterHa, "nature.pipeline.label_green_ha": np.LabelGreenHa,
		"nature.pipeline.named_water_ha": np.NamedWaterHa, "nature.pipeline.area_name_water_m": np.AreaNameWaterM,
		"nature.pipeline.area_name_park_m": np.AreaNameParkM, "nature.pipeline.big_park_ha": np.BigParkHa,
		"nature.pipeline.wood_cover_ha": np.WoodCoverHa, "nature.pipeline.street_tree_snap_m": np.StreetTreeSnapM,
		"nature.pipeline.tree_min_spacing_m": np.TreeMinSpacingM, "nature.pipeline.tree_row_step_m": np.TreeRowStepM, "nature.pipeline.deck_tree_margin_m": np.DeckTreeMarginM,
		"flow.gap_close_m": t.Flow.GapCloseM,
		"models.max_tris":  float64(t.Models.MaxTris), "models.max_tris_exception": float64(t.Models.MaxTrisException),
		"models.city_max_tris": float64(t.Models.CityMaxTris), "models.city_max_bytes": float64(t.Models.CityMaxBytes),
		"models.min_detail_m": t.Models.MinDetailM, "models.max_detail_m": t.Models.MaxDetailM, "models.detail_step_m": t.Models.DetailStepM,
		"models.near_m": t.Models.NearM, "models.hysteresis_m": t.Models.HysteresisM, "models.max_full": float64(t.Models.MaxFull),
		"models.roof_plan_max_polys": float64(t.Models.RoofPlanMaxPolys), "models.weld_m": t.Models.WeldM,
		"models.plan_simplify_m": t.Models.PlanSimplifyM, "models.replace_share": t.Models.ReplaceShare,
		"models.foot_tolerance_m": t.Models.FootTolM, "models.max_offset_m": t.Models.MaxOffsetM,
		"models.copper_min_top_m": t.Models.CopperMinTopM, "models.copper_slender": t.Models.CopperSlender,
		"models.bridge_end_m": t.Models.BridgeEndM, "models.bridge_clear_m": t.Models.BridgeClearM, "models.bridge_below_m": t.Models.BridgeBelowM,
		"models.ground_float_m": t.Models.GroundFloatM, "models.part_box_slack_m": t.Models.PartBoxSlackM,
	} {
		if v <= 0 {
			return fmt.Errorf("tuning.yaml: %s missing or not positive", name)
		}
	}
	for _, k := range []string{"motorway", "trunk", "primary", "secondary", "tertiary", "alley"} {
		if tt.MaxGrade[k] <= 0 {
			return fmt.Errorf("tuning.yaml: terrain.max_grade.%s missing", k)
		}
	}
	for _, k := range []string{"S", "M", "L"} {
		if nt.TreeSizes[k].CrownR <= 0 {
			return fmt.Errorf("tuning.yaml: nature.tree_sizes.%s missing", k)
		}
	}
	for _, k := range []string{"wood", "parkland", "garden", "cemetery"} {
		if nt.TreesPerHa[k] <= 0 {
			return fmt.Errorf("tuning.yaml: nature.trees_per_ha.%s missing", k)
		}
	}
	if len(np.TreeSizeMix) != 3 {
		return fmt.Errorf("tuning.yaml: nature.pipeline.tree_size_mix needs S, M, L")
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
	// DeckHeightM is the deck height above water of an iconic bridge (specs/terrain.md pins);
	// it applies to bridge edges named like the landmark.
	DeckHeightM float64 `yaml:"deck_height_m"`
}

type Spot struct {
	ID       string  `yaml:"id"`
	Kind     string  `yaml:"kind"`
	Name     string  `yaml:"name"`
	Lat      float64 `yaml:"lat"`
	Lon      float64 `yaml:"lon"`
	Minigame string  `yaml:"minigame"`
	// Photo spots (specs/photo.md): the view to frame and its radius.
	Look     *LatLon `yaml:"look"`
	SubjectM float64 `yaml:"subject_m"`
}

// Content is everything citypack reads for one city.
type Content struct {
	City      City
	Tuning    Tuning
	Landmarks []Landmark
	Spots     []Spot
	Models    *ModelsFile // nil without models.yaml
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
	if p := filepath.Join(dir, "models.yaml"); fileExists(p) {
		c.Models = &ModelsFile{}
		if err := readYAML(p, c.Models); err != nil {
			return nil, err
		}
	}
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

func fileExists(p string) bool { _, err := os.Stat(p); return err == nil }

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

// NameSQL is the DuckDB expression for a feature's display name. Without name_langs it is
// names.primary; with them the first non-null names.common[lang] wins and names.primary is used
// only when it is in Latin script (clients' fonts carry no CJK glyphs).
func (c *City) NameSQL() string {
	if len(c.NameLangs) == 0 {
		return "names.primary"
	}
	expr := "coalesce("
	for _, l := range c.NameLangs {
		expr += fmt.Sprintf("names.common['%s'], ", l)
	}
	expr += `CASE WHEN regexp_full_match(names.primary, '[\x{20}-\x{7E}\x{A0}-\x{24F}\x{1E00}-\x{1EFF}]*') THEN names.primary END)`
	return expr
}
