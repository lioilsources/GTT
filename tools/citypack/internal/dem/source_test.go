package dem

import (
	"math"
	"os"
	"path/filepath"
	"testing"
)

func TestReadASCSamplesBilinearAndNoData(t *testing.T) {
	dir := t.TempDir()
	// 3×2 cells of 0.001°, lower-left corner at (10, 50); rows go north to south.
	asc := "ncols 3\nnrows 2\nxllcorner 10\nyllcorner 50\ncellsize 0.001\nNODATA_value -9999\n" +
		"10 20 -9999\n30 40 50\n"
	if err := os.WriteFile(filepath.Join(dir, "a.asc"), []byte(asc), 0o644); err != nil {
		t.Fatal(err)
	}
	s, err := LocalASC(dir)
	if err != nil || s == nil {
		t.Fatalf("LocalASC: %v %v", s, err)
	}
	// Centre of the north-west cell.
	if z, ok := s.At(10.0005, 50.0015); !ok || math.Abs(z-10) > 1e-6 {
		t.Errorf("nw cell = %v %v, want 10", z, ok)
	}
	// Halfway between the four western cell centres.
	if z, ok := s.At(10.001, 50.001); !ok || math.Abs(z-25) > 1e-6 {
		t.Errorf("middle = %v %v, want 25", z, ok)
	}
	if _, ok := s.At(10.002, 50.001); ok {
		t.Error("a sample touching the no-data cell must fail")
	}
	if _, ok := s.At(9.9, 50.001); ok {
		t.Error("outside the grid must fail")
	}
	if !s.Lidar() {
		t.Error("local grids are lidar resolution")
	}
}

func TestHillshadeFlatIsCosZenith(t *testing.T) {
	g := NewGrid(4, 4)
	for _, v := range Hillshade(g, 8, 315, 45) {
		if math.Abs(v-math.Cos(math.Pi/4)) > 1e-9 {
			t.Fatalf("flat shade = %v, want cos 45°", v)
		}
	}
	// A slope facing the north-west sun is brighter than one facing away.
	nw, se := NewGrid(3, 3), NewGrid(3, 3)
	for y := 0; y < 3; y++ {
		for x := 0; x < 3; x++ {
			// Row 0 is north: rising to the south-east faces north-west.
			nw.Data[y*3+x] = float32(x + y)
			se.Data[y*3+x] = -float32(x + y)
		}
	}
	if a, b := Hillshade(nw, 1, 315, 45)[4], Hillshade(se, 1, 315, 45)[4]; a <= b {
		t.Errorf("north-west facing %v should be brighter than south-east facing %v", a, b)
	}
}
