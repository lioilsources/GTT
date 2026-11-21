// Package msync copies runtime shared files into both clients (DUALSTACK 5.2):
// app/assets/shared/ and web/public/shared/, both gitignored, rebuilt on every run.
package msync

import (
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"

	"metro/internal/repo"
)

type Config struct {
	BundleCities []string `yaml:"bundle_cities"`
}

type lockEntry struct {
	Version string `yaml:"version"`
}

func Sync(root string) error {
	var cfg Config
	if err := readYAML(filepath.Join(root, repo.GuardConfig), &cfg); err != nil {
		return err
	}
	var lock struct {
		Packs map[string]lockEntry `yaml:"packs"`
	}
	_ = readYAML(filepath.Join(root, repo.PacksLock), &lock) // optional before the first publish

	app, web := filepath.Join(root, repo.AppShared), filepath.Join(root, repo.WebShared)
	for _, d := range []string{app, web} {
		if err := os.RemoveAll(d); err != nil {
			return err
		}
	}
	// tuning: YAML for the app, JSON for the web.
	if err := copyFile(filepath.Join(root, repo.Tuning), filepath.Join(app, "content", "tuning.yaml")); err != nil {
		return err
	}
	var tuning any
	if err := readYAML(filepath.Join(root, repo.Tuning), &tuning); err != nil {
		return err
	}
	if err := writeJSON(filepath.Join(web, "content", "tuning.json"), tuning); err != nil {
		return err
	}
	for _, dir := range []string{repo.Cars, repo.Bench} {
		files, _ := filepath.Glob(filepath.Join(root, dir, "*.json"))
		for _, c := range files {
			for _, d := range []string{app, web} {
				if err := copyFile(c, filepath.Join(d, "content", filepath.Base(dir), filepath.Base(c))); err != nil {
					return err
				}
			}
		}
	}
	// assets/ as is (README files excluded).
	err := filepath.WalkDir(filepath.Join(root, repo.Assets), func(p string, e os.DirEntry, err error) error {
		if err != nil || e.IsDir() || strings.EqualFold(e.Name(), "README.md") {
			return err
		}
		rel, _ := filepath.Rel(filepath.Join(root, repo.Assets), p)
		for _, d := range []string{app, web} {
			if err := copyFile(p, filepath.Join(d, "assets", rel)); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	// City packs: bundled cities into the app, all built packs into the web under a version dir.
	for _, city := range cfg.BundleCities {
		src := filepath.Join(root, repo.Packs, city)
		if _, err := os.Stat(filepath.Join(src, "manifest.pb")); err != nil {
			return fmt.Errorf("pack %s missing in %s: run `citypack pull` (or `citypack build %s`)", city, repo.Packs, city)
		}
		ver := "local"
		if e, ok := lock.Packs[city]; ok {
			ver = e.Version
		}
		if err := copyDir(src, filepath.Join(app, "packs", city)); err != nil {
			return err
		}
		if err := copyDir(src, filepath.Join(web, "packs", city, ver)); err != nil {
			return err
		}
		if err := writeJSON(filepath.Join(web, "packs", city, "current.json"), map[string]string{"version": ver}); err != nil {
			return err
		}
	}
	slog.Info("sync", "app", repo.AppShared, "web", repo.WebShared)
	return nil
}

func readYAML(path string, v any) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return yaml.Unmarshal(b, v)
}

func writeJSON(path string, v any) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(b, '\n'), 0o644)
}

func copyFile(src, dst string) error {
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

func copyDir(src, dst string) error {
	return filepath.WalkDir(src, func(p string, e os.DirEntry, err error) error {
		if err != nil || e.IsDir() {
			return err
		}
		rel, _ := filepath.Rel(src, p)
		return copyFile(p, filepath.Join(dst, rel))
	})
}
