package gen

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Proto runs protoc for Dart (shared_gen), TypeScript (web/src/gen/pb, protoc-gen-es from
// web/node_modules) and Go (citypack). Plugin versions are pinned in docs/metro.md and CI.
func Proto(o *Output, protoDir string) error {
	protos, err := filepath.Glob(filepath.Join(o.Root, protoDir, "*.proto"))
	if err != nil || len(protos) == 0 {
		return fmt.Errorf("no .proto files in %s", protoDir)
	}
	esPlugin := filepath.Join(o.Root, "web", "node_modules", ".bin", "protoc-gen-es")
	if _, err := os.Stat(esPlugin); err != nil {
		return fmt.Errorf("protoc-gen-es missing: run `npm ci` in web/ first")
	}
	targets := []struct {
		flag, out string
		args      []string
	}{
		{"--dart_out", "packages/shared_gen/lib/src/pb", nil},
		{"--es_out", "web/src/gen/pb", []string{"--plugin=protoc-gen-es=" + esPlugin, "--es_opt=target=ts"}},
		{"--go_out", "tools/citypack/internal/pb", []string{"--go_opt=paths=source_relative"}},
	}
	for _, t := range targets {
		tmp, err := os.MkdirTemp("", "metro-proto-*")
		if err != nil {
			return err
		}
		defer os.RemoveAll(tmp)
		args := append([]string{"-I" + filepath.Join(o.Root, protoDir), t.flag + "=" + tmp}, t.args...)
		for _, p := range protos {
			args = append(args, filepath.Base(p))
		}
		cmd := exec.Command("protoc", args...)
		cmd.Dir = filepath.Join(o.Root, protoDir)
		if out, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf("protoc %s: %w\n%s\nneeds protoc, protoc-gen-dart (dart pub global activate protoc_plugin) and protoc-gen-go on PATH", t.flag, err, out)
		}
		o.Own(t.out)
		err = filepath.WalkDir(tmp, func(path string, e os.DirEntry, err error) error {
			if err != nil || e.IsDir() {
				return err
			}
			b, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			rel, _ := filepath.Rel(tmp, path)
			o.Add(filepath.Join(t.out, rel), normalizeProto(b))
			return nil
		})
		if err != nil {
			return err
		}
	}
	return nil
}

// normalizeProto drops version lines that differ between machines (protoc path in Go output).
func normalizeProto(b []byte) []byte {
	lines := strings.Split(string(b), "\n")
	out := lines[:0]
	for _, l := range lines {
		if strings.HasPrefix(l, "// \tprotoc ") || strings.HasPrefix(l, "//  protoc ") {
			continue
		}
		out = append(out, l)
	}
	return []byte(strings.Join(out, "\n"))
}
