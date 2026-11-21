// Command citypack builds a city package from Overture Maps data (METROPOLE_PLAN 5.3).
package main

import (
	"flag"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"time"

	"citypack/internal/config"
	"citypack/internal/steps"
)

type step struct {
	name string
	run  func(*steps.Env) error
}

var pipeline = []step{
	{"fetch", steps.Fetch},
	{"roads", steps.Roads},
	{"widen", steps.Widen},
	{"buildings", steps.Buildings},
	{"ground", steps.Ground},
	{"landmarks", steps.Landmarks},
	{"spots", steps.Spots},
	{"pack", steps.Pack},
	{"validate", steps.Validate},
	{"preview", steps.Preview},
}

func usage() {
	fmt.Fprintf(os.Stderr, "usage: citypack [flags] <step|build|publish> <city> | citypack pull <city|all>\nsteps:")
	for _, s := range pipeline {
		fmt.Fprintf(os.Stderr, " %s", s.name)
	}
	fmt.Fprintln(os.Stderr)
	flag.PrintDefaults()
}

func main() {
	root := flag.String("root", ".", "repository root (contains content/ and run/)")
	out := flag.String("out", "", "output directory (default build/packs/<city>)")
	force := flag.Bool("force", false, "ignore cached step outputs (except downloads)")
	refetch := flag.Bool("refetch", false, "re-download Overture layers")
	flag.Usage = usage
	flag.Parse()
	if flag.NArg() != 2 {
		usage()
		os.Exit(2)
	}
	cmd, city := flag.Arg(0), flag.Arg(1)
	if cmd == "pull" {
		var cities []string
		if city != "all" {
			cities = []string{city}
		}
		if err := steps.Pull(*root, cities); err != nil {
			slog.Error("citypack pull failed", "err", err)
			os.Exit(1)
		}
		return
	}
	if err := run(*root, *out, cmd, city, *force, *refetch); err != nil {
		slog.Error("citypack failed", "err", err)
		os.Exit(1)
	}
}

func run(root, out, cmd, city string, force, refetch bool) error {
	c, err := config.Load(filepath.Join(root, "content"), city)
	if err != nil {
		return err
	}
	if out == "" {
		out = filepath.Join(root, "build", "packs", city)
	}
	env, err := steps.NewEnv(c, filepath.Join(root, "run", "citypack", city), out, force)
	if err != nil {
		return err
	}
	env.Refetch = refetch
	if cmd == "publish" {
		return steps.Publish(env, root)
	}
	var todo []step
	for _, s := range pipeline {
		if cmd == "build" || cmd == s.name {
			todo = append(todo, s)
		}
	}
	if len(todo) == 0 {
		return fmt.Errorf("unknown step %q", cmd)
	}
	for _, s := range todo {
		start := time.Now()
		slog.Info("step", "name", s.name, "city", city)
		if err := s.run(env); err != nil {
			return fmt.Errorf("%s: %w", s.name, err)
		}
		slog.Info("step done", "name", s.name, "took", time.Since(start).Round(time.Millisecond))
	}
	return nil
}
