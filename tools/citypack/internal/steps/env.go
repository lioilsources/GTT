// Package steps implements the citypack pipeline steps (METROPOLE_PLAN 5.3).
package steps

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"

	"citypack/internal/config"
	"citypack/internal/geo"
)

// Env is shared by all steps of one city build.
type Env struct {
	C     *config.Content
	Work  string // run/citypack/<city>: cache of intermediate files
	Out   string // final citypack directory
	Proj  geo.Projection
	Force bool
	// Refetch re-downloads Overture layers; Force alone keeps them.
	Refetch bool
}

func NewEnv(c *config.Content, work, out string, force bool) (*Env, error) {
	for _, d := range []string{work, filepath.Join(work, "raw"), out} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			return nil, err
		}
	}
	return &Env{C: c, Work: work, Out: out, Proj: geo.NewProjection(c.City.Origin.Lat, c.City.Origin.Lon), Force: force}, nil
}

func (e *Env) W(name string) string   { return filepath.Join(e.Work, name) }
func (e *Env) Raw(name string) string { return filepath.Join(e.Work, "raw", name+".parquet") }

// fresh reports whether a cached output exists and the step may be skipped.
func (e *Env) fresh(path string) bool {
	if e.Force {
		return false
	}
	_, err := os.Stat(path)
	return err == nil
}

// AreaRingM is the area polygon in local metres.
func (e *Env) AreaRingM() []geo.Pt {
	r := make([]geo.Pt, 0, len(e.C.City.AreaRing))
	for _, p := range e.C.City.AreaRing {
		r = append(r, e.Proj.Forward(p[0], p[1]))
	}
	return geo.OpenRing(r)
}

// projSQL wraps a WGS84 geometry expression into the local projection.
func (e *Env) projSQL(expr string) string {
	return fmt.Sprintf("ST_Transform(%s, 'OGC:CRS84', '%s')", expr, e.C.City.ProjString())
}

func writeJSON(path string, v any) error {
	b, err := json.Marshal(v)
	if err != nil {
		return err
	}
	return os.WriteFile(path, b, 0o644)
}

func readJSON(path string, v any) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("%s missing, run the previous step first: %w", filepath.Base(path), err)
	}
	return json.Unmarshal(b, v)
}

func skip(step, path string) {
	slog.Info("cached, skipping", "step", step, "file", filepath.Base(path))
}
