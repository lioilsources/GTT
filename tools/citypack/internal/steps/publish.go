package steps

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"io/fs"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

// Built packs are not in git (DUALSTACK 5.1): `publish` uploads them as GitHub Release assets
// and records them in packs.lock; `pull` downloads what packs.lock names, so CI never builds packs.
// Browsers cannot fetch Release assets (github.com redirects without CORS headers), so the web
// client copies packs into its build instead of downloading them at run time.

// LockEntry is one city in packs.lock.
type LockEntry struct {
	Version         string `yaml:"version"`
	Tag             string `yaml:"tag"`
	Asset           string `yaml:"asset"`
	SHA256          string `yaml:"sha256"`
	OvertureRelease string `yaml:"overture_release"`
}

type Lock struct {
	Packs map[string]LockEntry `yaml:"packs"`
}

const lockHeader = "# Written by `citypack publish`; read by `citypack pull` and `metro sync`. Do not edit by hand.\n"

func ReadLock(root string) (*Lock, error) {
	l := &Lock{Packs: map[string]LockEntry{}}
	b, err := os.ReadFile(filepath.Join(root, "packs.lock"))
	if os.IsNotExist(err) {
		return l, nil
	}
	if err != nil {
		return nil, err
	}
	if err := yaml.Unmarshal(b, l); err != nil {
		return nil, fmt.Errorf("packs.lock: %w", err)
	}
	if l.Packs == nil {
		l.Packs = map[string]LockEntry{}
	}
	return l, nil
}

func (l *Lock) Write(root string) error {
	b, err := yaml.Marshal(l)
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(root, "packs.lock"), append([]byte(lockHeader), b...), 0o644)
}

// Tarball makes a deterministic tar.gz of a pack directory (sorted names, no times or owners).
func Tarball(dir string) ([]byte, error) {
	var files []string
	err := filepath.WalkDir(dir, func(p string, e fs.DirEntry, err error) error {
		if err != nil || e.IsDir() || strings.HasPrefix(e.Name(), ".") {
			return err
		}
		rel, _ := filepath.Rel(dir, p)
		files = append(files, filepath.ToSlash(rel))
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Strings(files)
	var buf bytes.Buffer
	zw, _ := gzip.NewWriterLevel(&buf, gzip.BestCompression)
	tw := tar.NewWriter(zw)
	for _, f := range files {
		b, err := os.ReadFile(filepath.Join(dir, f))
		if err != nil {
			return nil, err
		}
		if err := tw.WriteHeader(&tar.Header{Name: f, Mode: 0o644, Size: int64(len(b)), Format: tar.FormatPAX}); err != nil {
			return nil, err
		}
		if _, err := tw.Write(b); err != nil {
			return nil, err
		}
	}
	if err := tw.Close(); err != nil {
		return nil, err
	}
	if err := zw.Close(); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func gh(args ...string) error {
	cmd := exec.Command("gh", args...)
	cmd.Stdout, cmd.Stderr = os.Stderr, os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("gh %s: %w", strings.Join(args, " "), err)
	}
	return nil
}

// Publish uploads build/packs/<city> as a release asset and pins it in packs.lock.
func Publish(e *Env, root string) error {
	tgz, err := Tarball(e.Out)
	if err != nil {
		return err
	}
	sum := sha256.Sum256(tgz)
	sha := hex.EncodeToString(sum[:])
	ver := sha[:12]
	city := e.C.City.ID
	lock, err := ReadLock(root)
	if err != nil {
		return err
	}
	if cur, ok := lock.Packs[city]; ok && cur.SHA256 == sha {
		slog.Info("publish: unchanged", "city", city, "version", ver)
		return nil
	}
	entry := LockEntry{
		Version: ver, Tag: "pack-" + city + "-" + ver, Asset: city + "-" + ver + ".tar.gz",
		SHA256: sha, OvertureRelease: e.C.City.OvertureRelease,
	}
	tmp, err := os.MkdirTemp("", "citypack-publish-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	file := filepath.Join(tmp, entry.Asset)
	if err := os.WriteFile(file, tgz, 0o644); err != nil {
		return err
	}
	notes := fmt.Sprintf("Citypack %s, Overture %s. © OpenStreetMap contributors (ODbL), Overture Maps Foundation.", city, entry.OvertureRelease)
	if err := gh("release", "create", entry.Tag, file, "--title", "Citypack "+city+" "+ver, "--notes", notes, "--latest=false"); err != nil {
		return err
	}
	lock.Packs[city] = entry
	slog.Info("publish", "city", city, "version", ver, "MB", fmt.Sprintf("%.1f", float64(len(tgz))/1e6))
	return lock.Write(root)
}

// Pull downloads the packs named in packs.lock into build/packs/<city> (skipping up-to-date ones).
func Pull(root string, cities []string) error {
	lock, err := ReadLock(root)
	if err != nil {
		return err
	}
	if len(cities) == 0 {
		for c := range lock.Packs {
			cities = append(cities, c)
		}
		sort.Strings(cities)
	}
	for _, city := range cities {
		e, ok := lock.Packs[city]
		if !ok {
			return fmt.Errorf("packs.lock has no %s: run `citypack publish %s` first", city, city)
		}
		dst := filepath.Join(root, "build", "packs", city)
		if v, err := os.ReadFile(filepath.Join(dst, ".version")); err == nil && strings.TrimSpace(string(v)) == e.Version {
			slog.Info("pull: up to date", "city", city, "version", e.Version)
			continue
		}
		tmp, err := os.MkdirTemp("", "citypack-pull-*")
		if err != nil {
			return err
		}
		defer os.RemoveAll(tmp)
		if err := gh("release", "download", e.Tag, "--pattern", e.Asset, "--dir", tmp); err != nil {
			return err
		}
		b, err := os.ReadFile(filepath.Join(tmp, e.Asset))
		if err != nil {
			return err
		}
		sum := sha256.Sum256(b)
		if got := hex.EncodeToString(sum[:]); got != e.SHA256 {
			return fmt.Errorf("%s: sha256 %s, packs.lock says %s", e.Asset, got, e.SHA256)
		}
		if err := os.RemoveAll(dst); err != nil {
			return err
		}
		if err := Untar(b, dst); err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(dst, ".version"), []byte(e.Version+"\n"), 0o644); err != nil {
			return err
		}
		slog.Info("pull", "city", city, "version", e.Version)
	}
	return nil
}

// Untar extracts a tar.gz made by Tarball into dir.
func Untar(tgz []byte, dir string) error {
	zr, err := gzip.NewReader(bytes.NewReader(tgz))
	if err != nil {
		return err
	}
	tr := tar.NewReader(zr)
	for {
		h, err := tr.Next()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		name := filepath.Clean(h.Name)
		if strings.HasPrefix(name, "..") || filepath.IsAbs(name) {
			return fmt.Errorf("unsafe path in pack: %s", h.Name)
		}
		p := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			return err
		}
		b, err := io.ReadAll(tr)
		if err != nil {
			return err
		}
		if err := os.WriteFile(p, b, 0o644); err != nil {
			return err
		}
	}
}
