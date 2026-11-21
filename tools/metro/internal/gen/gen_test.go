package gen

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNames(t *testing.T) {
	for in, want := range map[string]string{"view_width_m": "viewWidthM", "top_default": "topDefault", "m0_coupe": "m0Coupe", "class": "class_"} {
		if got := Field(in); got != want {
			t.Errorf("Field(%q) = %q, want %q", in, got, want)
		}
	}
	if Pascal("lanes_by_class") != "LanesByClass" {
		t.Error("Pascal")
	}
}

func TestColorARGB(t *testing.T) {
	if c, _ := colorARGB("#1C1C22"); c != 0xFF1C1C22 {
		t.Errorf("rgb: %08X", c)
	}
	if c, _ := colorARGB("#15151BAA"); c != 0xAA15151B {
		t.Errorf("rgba: %08X", c)
	}
	if _, ok := colorARGB("red"); ok {
		t.Error("named colours must be rejected")
	}
}

func TestTuningTypesFromLiterals(t *testing.T) {
	dir := t.TempDir()
	src := "a_b: 1\nc: 2.5\nm: {x: 1.0, y: 2.0}  # doc\nl: [1.0, 2.0]\n"
	if err := os.WriteFile(filepath.Join(dir, "t.yaml"), []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	o := NewOutput(dir)
	if err := Tuning(o, "t.yaml"); err != nil {
		t.Fatal(err)
	}
	d := string(o.Files["packages/shared_gen/lib/src/tuning.g.dart"])
	for _, want := range []string{"int aB;", "double c;", "final TuningM m;", "List<double> l;", "/// doc", "double? operator []"} {
		if !strings.Contains(d, want) {
			t.Errorf("dart output lacks %q", want)
		}
	}
	if err := os.WriteFile(filepath.Join(dir, "t.yaml"), []byte("l: [1, 2.0]\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := Tuning(NewOutput(dir), "t.yaml"); err == nil {
		t.Error("mixed int/float list must be an error")
	}
}

func TestCheckReportsDriftAndStaleFiles(t *testing.T) {
	dir := t.TempDir()
	o := NewOutput(dir)
	o.Own("gen")
	o.Add("gen/a.txt", []byte("A"))
	if err := o.Write(); err != nil {
		t.Fatal(err)
	}
	if bad, _ := o.Check(); len(bad) != 0 {
		t.Fatalf("fresh output reported %v", bad)
	}
	_ = os.WriteFile(filepath.Join(dir, "gen", "a.txt"), []byte("B"), 0o644)
	_ = os.WriteFile(filepath.Join(dir, "gen", "old.txt"), []byte("x"), 0o644)
	bad, _ := o.Check()
	if len(bad) != 2 {
		t.Fatalf("want differs + stale, got %v", bad)
	}
}
