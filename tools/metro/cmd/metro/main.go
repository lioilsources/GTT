// Command metro maintains the shared layer of the Metropole monorepo (DUALSTACK 5).
//
//	metro gen [--check]                 generate shared_gen (Dart) and web/src/gen (TS)
//	metro sync                          copy runtime files into app/assets/shared and web/public/shared
//	metro validate                      check content against schema/
//	metro guard [--base origin/main]    fail when a branch touches paths of another session
//	metro vectors check                 validate vector files
//	metro vectors record --client C --module M
//	metro parity report [--release]     write PARITY.md, fail on red rows
//	metro progress [--tests|--check]    write plans/PROGRESS.md and the README status block (--check: fail if stale)
//	metro stats                         write plans/STATS.md (numbers for the launch post)
package main

import (
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"time"

	"metro/internal/gen"
	"metro/internal/guard"
	"metro/internal/msync"
	"metro/internal/parity"
	"metro/internal/progress"
	"metro/internal/repo"
	"metro/internal/stats"
	"metro/internal/validate"
	"metro/internal/vectors"
)

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	root, err := repo.Root()
	if err != nil {
		fail(err)
	}
	args := os.Args[2:]
	switch os.Args[1] {
	case "gen":
		fs := flag.NewFlagSet("gen", flag.ExitOnError)
		check := fs.Bool("check", false, "compare with the committed files instead of writing")
		_ = fs.Parse(args)
		fail(runGen(root, *check))
	case "sync":
		fail(msync.Sync(root))
	case "validate":
		failAll(validate.Run(root))
		slog.Info("validate ok")
	case "guard":
		fs := flag.NewFlagSet("guard", flag.ExitOnError)
		base := fs.String("base", "origin/main", "branch the PR targets")
		_ = fs.Parse(args)
		fail(runGuard(root, *base))
	case "vectors":
		if len(args) == 0 {
			usage()
		}
		switch args[0] {
		case "check":
			failAll(vectors.Check(root))
			slog.Info("vectors ok")
		case "record":
			fs := flag.NewFlagSet("record", flag.ExitOnError)
			client := fs.String("client", "", "lead client: flutter or web")
			module := fs.String("module", "", "module id, e.g. prng")
			_ = fs.Parse(args[1:])
			fail(vectors.Record(root, *client, *module))
		default:
			usage()
		}
	case "parity":
		fs := flag.NewFlagSet("parity", flag.ExitOnError)
		release := fs.Bool("release", false, "fail when a done client is not checked")
		if len(args) == 0 || args[0] != "report" {
			usage()
		}
		_ = fs.Parse(args[1:])
		red, err := parity.Report(root, *release)
		fail(err)
		if len(red) > 0 {
			fail(fmt.Errorf("red rows:\n  %s", strings.Join(red, "\n  ")))
		}
		slog.Info("parity green", "report", "PARITY.md")
	case "progress":
		fs := flag.NewFlagSet("progress", flag.ExitOnError)
		tests := fs.Bool("tests", false, "run every test suite and record the counts")
		check := fs.Bool("check", false, "fail when the README status block is stale (writes nothing)")
		_ = fs.Parse(args)
		fail(runProgress(root, *tests, *check))
	case "stats":
		md, err := stats.Render(root)
		fail(err)
		fail(os.WriteFile(filepath.Join(root, "plans", "STATS.md"), []byte(md), 0o644))
		slog.Info("stats", "file", "plans/STATS.md")
	default:
		usage()
	}
}

func runProgress(root string, tests, check bool) error {
	now := time.Now()
	if check {
		f, err := progress.Load(root)
		if err != nil {
			return err
		}
		block, err := progress.StatusBlock(root, f, now)
		if err != nil {
			return err
		}
		readme, err := os.ReadFile(filepath.Join(root, "README.md"))
		if err != nil {
			return err
		}
		stale, err := progress.StatusStale(string(readme), block)
		if err != nil {
			return err
		}
		if stale {
			return fmt.Errorf("README.md status block is stale: run metro progress")
		}
		slog.Info("progress --check ok")
		return nil
	}
	if tests {
		total, pass, err := progress.RunTests(root)
		if err != nil {
			return err
		}
		if err := progress.SetTests(root, total, pass, now); err != nil {
			return err
		}
		slog.Info("tests", "total", total, "passing", pass)
	}
	f, err := progress.Load(root)
	if err != nil {
		return err
	}
	md, err := progress.Render(root, f, now)
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(root, "plans", "PROGRESS.md"), []byte(md), 0o644); err != nil {
		return err
	}
	block, err := progress.StatusBlock(root, f, now)
	if err != nil {
		return err
	}
	rp := filepath.Join(root, "README.md")
	readme, err := os.ReadFile(rp)
	if err != nil {
		return err
	}
	out, err := progress.ReplaceStatus(string(readme), block)
	if err != nil {
		return err
	}
	slog.Info("progress", "file", "plans/PROGRESS.md", "readme", "status block")
	return os.WriteFile(rp, []byte(out), 0o644)
}

func runGen(root string, check bool) error {
	o := gen.NewOutput(root)
	o.Own("web/src/gen")
	o.Own("packages/shared_gen/lib/src")
	steps := []func() error{
		func() error { return gen.Tuning(o, repo.Tuning) },
		func() error { return gen.Tokens(o, repo.Tokens) },
		func() error { return gen.I18n(o, repo.I18n) },
		func() error { return gen.Ids(o, repo.Cities, repo.Cars, repo.Catalog) },
		func() error { return gen.Schema(o, repo.Schema) },
		func() error { return gen.Proto(o, repo.Proto) },
	}
	for _, s := range steps {
		if err := s(); err != nil {
			return err
		}
	}
	if !check {
		if err := o.Write(); err != nil {
			return err
		}
		slog.Info("gen", "files", len(o.Files))
		return nil
	}
	bad, err := o.Check()
	if err != nil {
		return err
	}
	if len(bad) > 0 {
		return fmt.Errorf("generated code is out of date, run `metro gen`:\n  %s", strings.Join(bad, "\n  "))
	}
	slog.Info("gen --check ok", "files", len(o.Files))
	return nil
}

func runGuard(root, base string) error {
	cfg, err := guard.Load(root)
	if err != nil {
		return err
	}
	branch, err := guard.CurrentBranch(root)
	if err != nil {
		return err
	}
	changed, err := guard.Changed(root, base)
	if err != nil {
		return err
	}
	bad, err := cfg.Violations(branch, changed)
	if err != nil {
		return err
	}
	if len(bad) > 0 {
		return fmt.Errorf("branch %s touches paths of another session:\n  %s", branch, strings.Join(bad, "\n  "))
	}
	slog.Info("guard ok", "branch", branch, "files", len(changed))
	return nil
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: metro gen [--check] | sync | validate | guard [--base B] | vectors check | vectors record --client C --module M | parity report [--release] | progress [--tests|--check] | stats")
	os.Exit(2)
}

func fail(err error) {
	if err != nil {
		slog.Error("metro failed", "err", err)
		os.Exit(1)
	}
}

func failAll(errs []error) {
	if len(errs) > 0 {
		fail(errors.Join(errs...))
	}
}
