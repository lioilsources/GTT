// Package duck runs SQL through the duckdb CLI binary.
//
// The CLI (not go-duckdb) is used so citypack stays CGO-free and builds the same
// on macOS arm64 and Linux arm64.
package duck

import (
	"bytes"
	"encoding/csv"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"strings"
	"time"
)

const preamble = `
INSTALL spatial; LOAD spatial;
INSTALL httpfs; LOAD httpfs;
SET geometry_always_xy = true;
SET s3_region = 'us-west-2';
`

// Bin is the duckdb executable; override with $DUCKDB.
func Bin() string {
	if b := os.Getenv("DUCKDB"); b != "" {
		return b
	}
	return "duckdb"
}

// Exec runs a SQL script and returns stdout (CSV mode).
func Exec(label, sql string) (string, error) {
	start := time.Now()
	cmd := exec.Command(Bin(), "-no-agent", "-bail", "-csv", ":memory:")
	cmd.Stdin = strings.NewReader(preamble + sql)
	var out, errb bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errb
	err := cmd.Run()
	stderr := filterWarnings(errb.String())
	if err != nil {
		return "", fmt.Errorf("duckdb %s: %w\n%s", label, err, stderr)
	}
	if strings.Contains(stderr, "Error") {
		return "", fmt.Errorf("duckdb %s: %s", label, stderr)
	}
	slog.Info("duckdb", "step", label, "took", time.Since(start).Round(time.Millisecond))
	return out.String(), nil
}

func filterWarnings(s string) string {
	var keep []string
	for _, l := range strings.Split(s, "\n") {
		if strings.Contains(l, "deprecated") || strings.Contains(l, "WARNING") || strings.TrimSpace(l) == "" {
			continue
		}
		keep = append(keep, l)
	}
	return strings.Join(keep, "\n")
}

// Quote returns a SQL string literal.
func Quote(s string) string { return "'" + strings.ReplaceAll(s, "'", "''") + "'" }

// Query runs a SELECT and returns its rows as CSV records (header excluded).
// Results go through a temp file because the preamble also prints to stdout.
func Query(label, setup, sel string) ([][]string, error) {
	f, err := os.CreateTemp("", "citypack-*.csv")
	if err != nil {
		return nil, err
	}
	path := f.Name()
	f.Close()
	defer os.Remove(path)
	if _, err := Exec(label, fmt.Sprintf("%s\nCOPY (%s) TO %s (FORMAT csv, HEADER true);", setup, sel, Quote(path))); err != nil {
		return nil, err
	}
	b, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer b.Close()
	recs, err := csv.NewReader(b).ReadAll()
	if err != nil {
		return nil, fmt.Errorf("duckdb %s: parse csv: %w", label, err)
	}
	if len(recs) == 0 {
		return nil, nil
	}
	return recs[1:], nil
}
