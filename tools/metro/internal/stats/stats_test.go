package stats

import (
	"testing"
	"time"
)

func TestSummarize(t *testing.T) {
	at := func(s string) time.Time {
		v, err := time.Parse(time.RFC3339, s)
		if err != nil {
			t.Fatal(err)
		}
		return v
	}
	all := []Commit{
		{at("2026-11-21T10:05:00Z"), "a"},
		{at("2026-11-21T10:40:00Z"), "Merge pull request #1 from x/y"},
		{at("2026-11-21T10:50:00Z"), "Merge pull request #2 from x/z"},
		{at("2026-11-21T12:10:00Z"), "Merge pull request #3 from x/w"},
		{at("2026-11-21T12:20:00Z"), "Merge branch 'main'"},
	}
	tl := Summarize(all, all[1:])
	if tl.Commits != 5 || tl.ActiveHours != 2 || tl.MergedPRs != 3 || tl.PeakPRs != 2 {
		t.Fatalf("got %+v", tl)
	}
	if !tl.PeakHour.Equal(at("2026-11-21T10:00:00Z")) || !tl.First.Equal(all[0].At) || !tl.Last.Equal(all[4].At) {
		t.Fatalf("got %+v", tl)
	}
}

func TestClassify(t *testing.T) {
	cases := []struct {
		path string
		lang string
		kind Kind
	}{
		{"web/src/main.ts", "TypeScript", Manual},
		{"web/src/gen/tuning.ts", "TypeScript", Generated},
		{"web/test/cars.test.ts", "TypeScript", Test},
		{"packages/drive_core/test/cars_test.dart", "Dart", Test},
		{"packages/shared_gen/lib/src/i18n.g.dart", "Dart", Generated},
		{"tools/metro/internal/stats/stats_test.go", "Go", Test},
		{"tools/citypack/internal/pb/citypack.pb.go", "Go", Generated},
		{"README.md", "", Manual},
	}
	for _, c := range cases {
		if l, k := Classify(c.path); l != c.lang || k != c.kind {
			t.Errorf("%s: got %q %d, want %q %d", c.path, l, k, c.lang, c.kind)
		}
	}
}
