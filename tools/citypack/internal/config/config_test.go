package config

import (
	"os"
	"strings"
	"testing"
)

// The real content must load, and dropping a pipeline key must fail loudly.
func TestLoadRealContentAndStrictTuning(t *testing.T) {
	c, err := Load("../../../../content", "nyc")
	if err != nil {
		t.Fatal(err)
	}
	if c.Tuning.Roads.LanesByClass["primary"] == 0 || len(c.Tuning.Buildings.HeightBandsM) == 0 {
		t.Fatalf("tuning not read: %+v", c.Tuning)
	}
	src, err := os.ReadFile("../../../../content/tuning.yaml")
	if err != nil {
		t.Fatal(err)
	}
	var tu Tuning
	broken := strings.Replace(string(src), "  merge_gap_m: 0.5", "", 1)
	if err := readYAMLBytes([]byte(broken), &tu); err != nil {
		t.Fatal(err)
	}
	if tu.check() == nil {
		t.Fatal("missing buildings.merge_gap_m must be an error")
	}
}
