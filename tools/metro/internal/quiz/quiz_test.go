package quiz

import (
	"path/filepath"
	"testing"
)

func q(id string, ans int, opts int) Question {
	o := make([]string, opts)
	for i := range o {
		o[i] = "x"
	}
	return Question{ID: id, Q: Text{En: "a", Cs: "b"}, Options: Options{En: o, Cs: o}, Answer: ans}
}

func TestCheck(t *testing.T) {
	if err := Check(Bank{Questions: []Question{q("a", 0, 4), q("b", 3, 4)}}); err != nil {
		t.Fatal(err)
	}
	bad := []Bank{
		{Questions: []Question{q("a", 0, 4), q("a", 1, 4)}},
		{Questions: []Question{q("a", 4, 4)}},
		{Questions: []Question{q("a", 0, 3)}},
		{Questions: []Question{q("", 0, 4)}},
	}
	for i, b := range bad {
		if Check(b) == nil {
			t.Errorf("bad bank %d passed", i)
		}
	}
}

func TestLoadRepoBanks(t *testing.T) {
	banks, err := Load(filepath.Join("..", "..", "..", "..", "content", "quiz"))
	if err != nil {
		t.Fatal(err)
	}
	for _, city := range []string{"nyc", "prague"} {
		if len(banks[city].Questions) < 4 {
			t.Errorf("%s bank too small", city)
		}
	}
}
