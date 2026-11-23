package progress

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestWindowRatesAndDaily(t *testing.T) {
	items := []Item{
		{Size: "L", Status: Hotovo, Done: "2026-11-18T10:00"},
		{Size: "M", Status: Ceka, Done: "2026-11-20T10:00"},
		{Size: "S", Status: Todo},
	}
	now := time.Date(2026, 11, 21, 12, 0, 0, 0, time.Local)
	daily := DailyPoints(items)
	if daily[time.Date(2026, 11, 18, 0, 0, 0, 0, time.Local)] != 4 {
		t.Fatalf("daily %v", daily)
	}
	fast, slow, ok := WindowRates(daily, now)
	// windows: 18–20 = 6/3, 19–21 = 2/3
	if !ok || fast != 2 || slow < 0.66 || slow > 0.67 {
		t.Fatalf("fast %v slow %v", fast, slow)
	}
}

func TestCheckRejectsDoneWithoutEvidence(t *testing.T) {
	f := &File{Milestones: []string{"M0"}, Items: []Item{{ID: "a", Milestone: "M0", Size: "S", Status: Hotovo, Done: "2026-11-21T10:00"}}}
	if f.check() == nil {
		t.Fatal("hotovo without evidence must fail")
	}
	f.Items[0].Evidence = "go test"
	if err := f.check(); err != nil {
		t.Fatal(err)
	}
	f.Items[0].Size = "XL"
	if f.check() == nil {
		t.Fatal("unknown size must fail")
	}
}

func TestCountContentMinigamesAndSkits(t *testing.T) {
	root := t.TempDir()
	write := func(rel, body string) {
		p := filepath.Join(root, rel)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	// Minigames come from the catalog, not from packages/mg_* (engines and shared code live there too).
	write("content/minigames/catalog.yaml", "engines: [cards]\nminigames:\n  - {id: a, engine: cards}\n  - {id: b, engine: cards}\n")
	write("packages/mg_a/pubspec.yaml", "name: mg_a\n")
	write("packages/mg_extra/pubspec.yaml", "name: mg_extra\n")
	write("content/npc/skits/a_1.yaml", "id: a_1\ncharacter: a\n")
	write("content/npc/skits/b_1.yaml", "id: b_1\ncharacter: b\n")
	write("content/npc/skits/README.md", "notes\n")
	write("content/npc/characters.yaml", "characters: []\n")
	got := map[string]string{}
	for _, c := range countContent(root, &File{}) {
		got[c.name] = c.value
	}
	if got["Minihry"] != "2" || got["Skity"] != "2" {
		t.Fatalf("Minihry=%s Skity=%s, want 2 and 2", got["Minihry"], got["Skity"])
	}
}

func TestStatusBlockReplaceAndStale(t *testing.T) {
	readme := "# X\n\n" + StatusOpen + "\nold\n" + StatusClose + "\n\nrest\n"
	block := StatusOpen + "\n| a | 1 |\n\n_Stav k 2026-11-23, generuje `metro progress`._\n" + StatusClose
	got, err := ReplaceStatus(readme, block)
	if err != nil || got != "# X\n\n"+block+"\n\nrest\n" {
		t.Fatalf("ReplaceStatus = %q, %v", got, err)
	}
	if stale, _ := StatusStale(readme, block); !stale {
		t.Fatal("old block must be stale")
	}
	later := strings.Replace(block, "2026-11-23", "2026-12-01", 1)
	if stale, _ := StatusStale(got, later); stale {
		t.Fatal("a different date alone must not make the block stale")
	}
	if _, err := ReplaceStatus("no markers", block); err == nil {
		t.Fatal("missing markers must fail")
	}
}

func TestVerifyPasses(t *testing.T) {
	v := &VerifyFile{PassMin: 30, Base: "https://x/", Checks: map[string]Check{
		"A": {City: "prague", Q: "city=prague", Min: 20, Client: "w", Expect: "a"},
		"B": {City: "nyc", Min: 25, Client: "w", Expect: "b"},
		"C": {City: "prague", Min: 15, Client: "w", Expect: "c"},
		"D": {City: "", Min: 5, Client: "decide", Expect: "d"},
		"E": {City: "nyc", Min: 5, Client: "w", Expect: "e"},
		"G": {City: "nyc", Min: 5, Client: "w", Expect: "g"},
	}}
	items := []Item{{ID: "A", Status: Ceka}, {ID: "B", Status: Ceka}, {ID: "C", Status: Ceka},
		{ID: "D", Status: Ceka}, {ID: "E", Status: Ceka}, {ID: "F", Status: Ceka}, {ID: "G", Status: Hotovo}}
	ps := Passes(items, v)
	got := []string{}
	for _, p := range ps {
		ids := []string{}
		for _, it := range p.items {
			ids = append(ids, it.ID)
		}
		got = append(got, p.city+":"+strings.Join(ids, ","))
	}
	// NYC first; B+E = 30 fits; Prague A (20) + C (15) > 30 → two passes; G is done, D a decision.
	if strings.Join(got, " ") != "nyc:B,E prague:A prague:C" {
		t.Fatalf("passes %v", got)
	}
	md := RenderVerify(&File{Items: items}, v, "2026-11-23 12:00")
	for _, want := range []string{"## Průchod 1 · New York · 30 min", "[`?city=prague`](https://x/?city=prague)", "## Rozhodnutí a měření", "## Bez návodu", "**F**"} {
		if !strings.Contains(md, want) {
			t.Errorf("verify.md misses %q", want)
		}
	}
}
