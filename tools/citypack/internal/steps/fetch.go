package steps

import (
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strings"

	"citypack/internal/duck"
)

// Layers fetched from Overture: local name → STAC collection.
var fetchLayers = []string{
	"segment", "connector", "building", "building_part",
	"water", "land", "land_use", "land_cover", "division_area", "place",
}

// Fetch downloads every Overture layer intersecting the area bbox into raw/<layer>.parquet.
// It uses the release's STAC item index to read only the files that overlap the bbox.
func Fetch(e *Env) error {
	idx := e.W("raw/stac-" + e.C.City.OvertureRelease + ".parquet")
	if _, err := os.Stat(idx); err != nil || e.Refetch {
		url := fmt.Sprintf("https://stac.overturemaps.org/%s/collections.parquet", e.C.City.OvertureRelease)
		if err := download(url, idx); err != nil {
			return fmt.Errorf("stac index: %w", err)
		}
	}
	x1, y1, x2, y2 := e.C.City.BBox()
	bboxCond := fmt.Sprintf("bbox.xmin <= %f AND bbox.xmax >= %f AND bbox.ymin <= %f AND bbox.ymax >= %f", x2, x1, y2, y1)
	for _, layer := range fetchLayers {
		out := e.Raw(layer)
		if _, err := os.Stat(out); err == nil && !e.Refetch {
			skip("fetch", out)
			continue
		}
		rows, err := duck.Query("stac "+layer, "", fmt.Sprintf(
			"SELECT assets.aws.href FROM read_parquet(%s) WHERE collection = %s AND %s",
			duck.Quote(idx), duck.Quote(layer), bboxCond))
		if err != nil {
			return err
		}
		var files []string
		for _, r := range rows {
			files = append(files, duck.Quote(r[0]))
		}
		if len(files) == 0 {
			return fmt.Errorf("fetch %s: no Overture files intersect the area", layer)
		}
		slog.Info("fetch", "layer", layer, "files", len(files))
		tmp := out + ".tmp"
		_, err = duck.Exec("fetch "+layer, fmt.Sprintf(
			"COPY (SELECT * FROM read_parquet([%s], union_by_name=true) WHERE %s) TO %s (FORMAT parquet);",
			strings.Join(files, ","), bboxCond, duck.Quote(tmp)))
		if err != nil {
			return err
		}
		if err := os.Rename(tmp, out); err != nil {
			return err
		}
	}
	return nil
}

func download(url, path string) error {
	resp, err := http.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("GET %s: %s", url, resp.Status)
	}
	f, err := os.Create(path + ".tmp")
	if err != nil {
		return err
	}
	if _, err := io.Copy(f, resp.Body); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	return os.Rename(path+".tmp", path)
}
