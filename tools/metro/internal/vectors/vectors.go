// Package vectors checks P0 vector files and re-records them with the lead client (DUALSTACK 5.4).
package vectors

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"metro/internal/repo"
	"metro/internal/validate"
)

type File struct {
	Module      string `json:"module"`
	SpecVersion int    `json:"specVersion"`
	Cases       []struct {
		Name string `json:"name"`
	} `json:"cases"`
}

// Check validates every vector file and that its module and spec version match specs/.
func Check(root string) []error {
	errs := validate.Run(root, "vector.schema.json")
	files, _ := filepath.Glob(filepath.Join(root, repo.Vectors, "*.json"))
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			errs = append(errs, err)
			continue
		}
		var v File
		if err := json.Unmarshal(b, &v); err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", filepath.Base(f), err))
			continue
		}
		if want := strings.TrimSuffix(filepath.Base(f), ".json"); v.Module != want {
			errs = append(errs, fmt.Errorf("%s: module %q must match the file name", filepath.Base(f), v.Module))
		}
		seen := map[string]bool{}
		for _, c := range v.Cases {
			if seen[c.Name] {
				errs = append(errs, fmt.Errorf("%s: duplicate case %q", filepath.Base(f), c.Name))
			}
			seen[c.Name] = true
		}
		if sv, err := SpecVersion(root, v.Module); err != nil {
			errs = append(errs, err)
		} else if sv != v.SpecVersion {
			errs = append(errs, fmt.Errorf("%s: specVersion %d, spec says %d", filepath.Base(f), v.SpecVersion, sv))
		}
	}
	return errs
}

// SpecVersion reads "version: N" from specs/<module>.md or specs/minigames/<module>.md.
func SpecVersion(root, module string) (int, error) {
	for _, p := range []string{filepath.Join(root, "specs", module+".md"), filepath.Join(root, "specs", "minigames", module+".md")} {
		b, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		for _, l := range strings.Split(string(b), "\n") {
			l = strings.ReplaceAll(l, "*", "")
			if i := strings.Index(l, "version:"); i >= 0 {
				var v int
				if _, err := fmt.Sscanf(strings.TrimSpace(l[i+len("version:"):]), "%d", &v); err == nil {
					return v, nil
				}
			}
		}
		return 0, fmt.Errorf("%s: no `version: N` line", p)
	}
	return 0, fmt.Errorf("vectors/%s.json: no spec specs/%s.md", module, module)
}

// Record replays vectors/<module>.json with the lead client's rules and rewrites the states.
// The recorder takes the file as its argument and rewrites it in place.
func Record(root, client, module string) error {
	file := filepath.Join(root, repo.Vectors, module+".json")
	if _, err := os.Stat(file); err != nil {
		return fmt.Errorf("%s missing: write the cases (config, seed, actions) first", file)
	}
	var cmd *exec.Cmd
	switch client {
	case "flutter":
		cmd = exec.Command("dart", "run", "rules_core:record", module, file)
		cmd.Dir = filepath.Join(root, "packages", "rules_core")
	case "web":
		cmd = exec.Command("npx", "tsx", "scripts/record.ts", module, file)
		cmd.Dir = filepath.Join(root, "web")
	default:
		return fmt.Errorf("unknown client %q (flutter|web)", client)
	}
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("record %s with %s: %w", module, client, err)
	}
	return nil
}
