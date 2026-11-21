// Package progress renders plans/PROGRESS.md from plans/progress.yaml (no lines of code, no commit counts).
package progress

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

const (
	Hotovo  = "hotovo"
	Ceka    = "čeká na Ol1na"
	Overeno = "ověřeno"
	Wip     = "wip"
	Todo    = "todo"
	timeFmt = "2006-01-02T15:04"
)

var points = map[string]int{"S": 1, "M": 2, "L": 4}

type Reopen struct {
	Date   string `yaml:"date"`
	Reason string `yaml:"reason"`
}

type Item struct {
	ID        string   `yaml:"id"`
	Milestone string   `yaml:"milestone"`
	Name      string   `yaml:"name"`
	Size      string   `yaml:"size"`
	Status    string   `yaml:"status"`
	Started   string   `yaml:"started"`
	Done      string   `yaml:"done"`
	Commit    string   `yaml:"commit"`
	Evidence  string   `yaml:"evidence"`
	Reopened  []Reopen `yaml:"reopened"`
}

func (i Item) Points() int { return points[i.Size] }

// Finished: the work is done (hotovo, ověřeno) – counts towards milestone completion.
func (i Item) Finished() bool { return i.Status == Hotovo || i.Status == Overeno }

// Left wip: finished or waiting for Ol1n – counts towards tempo.
func (i Item) Delivered() bool { return i.Finished() || i.Status == Ceka }

type FPS struct {
	App      *float64 `yaml:"app"`
	Web      *float64 `yaml:"web"`
	Measured *string  `yaml:"measured"`
}

type File struct {
	Milestones []string `yaml:"milestones"`
	Items      []Item   `yaml:"items"`
	Counters   struct {
		Tests struct {
			Total    int     `yaml:"total"`
			Passing  int     `yaml:"passing"`
			Measured *string `yaml:"measured"`
		} `yaml:"tests"`
		FPS map[string]FPS `yaml:"fps"`
	} `yaml:"counters"`
}

const Path = "plans/progress.yaml"

func Load(root string) (*File, error) {
	b, err := os.ReadFile(filepath.Join(root, Path))
	if err != nil {
		return nil, err
	}
	var f File
	if err := yaml.Unmarshal(b, &f); err != nil {
		return nil, fmt.Errorf("%s: %w", Path, err)
	}
	return &f, f.check()
}

func (f *File) check() error {
	ms := map[string]bool{}
	for _, m := range f.Milestones {
		ms[m] = true
	}
	ids := map[string]bool{}
	for _, it := range f.Items {
		switch {
		case ids[it.ID]:
			return fmt.Errorf("progress: duplicate id %s", it.ID)
		case !ms[it.Milestone]:
			return fmt.Errorf("progress: %s has unknown milestone %s", it.ID, it.Milestone)
		case points[it.Size] == 0:
			return fmt.Errorf("progress: %s size must be S, M or L", it.ID)
		}
		ids[it.ID] = true
		switch it.Status {
		case Todo, Wip:
		case Hotovo, Overeno:
			if it.Evidence == "" || it.Done == "" {
				return fmt.Errorf("progress: %s is %s without evidence and done date", it.ID, it.Status)
			}
		case Ceka:
			if it.Done == "" {
				return fmt.Errorf("progress: %s waits for Ol1n without a done date", it.ID)
			}
		default:
			return fmt.Errorf("progress: %s has unknown status %q", it.ID, it.Status)
		}
		for _, t := range []string{it.Started, it.Done} {
			if t != "" {
				if _, err := time.ParseInLocation(timeFmt, t, time.Local); err != nil {
					return fmt.Errorf("progress: %s: bad time %q (want %s)", it.ID, t, timeFmt)
				}
			}
		}
	}
	return nil
}

func parse(t string) time.Time {
	v, _ := time.ParseInLocation(timeFmt, t, time.Local)
	return v
}

func day(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, t.Location())
}

// DailyPoints sums delivered points per calendar day.
func DailyPoints(items []Item) map[time.Time]int {
	out := map[time.Time]int{}
	for _, it := range items {
		if it.Delivered() && it.Done != "" {
			out[day(parse(it.Done))] += it.Points()
		}
	}
	return out
}

// WindowRates returns the fastest and slowest non-zero 3-day window rate (points per day)
// from the first delivery to today.
func WindowRates(daily map[time.Time]int, now time.Time) (fast, slow float64, ok bool) {
	if len(daily) == 0 {
		return 0, 0, false
	}
	first := day(now)
	for d := range daily {
		if d.Before(first) {
			first = d
		}
	}
	end := day(now)
	start := first
	if end.Sub(start) < 48*time.Hour {
		start = end.AddDate(0, 0, -2)
	}
	fast, slow = 0, -1
	for s := start; !s.AddDate(0, 0, 2).After(end); s = s.AddDate(0, 0, 1) {
		sum := 0
		for k := 0; k < 3; k++ {
			sum += daily[s.AddDate(0, 0, k)]
		}
		r := float64(sum) / 3
		if r > fast {
			fast = r
		}
		if r > 0 && (slow < 0 || r < slow) {
			slow = r
		}
	}
	return fast, slow, fast > 0
}

type counter struct {
	name, value, target string
}

func countContent(root string, f *File) []counter {
	var out []counter
	mg := 0
	if dirs, err := filepath.Glob(filepath.Join(root, "packages", "mg_*")); err == nil {
		for _, d := range dirs {
			b := filepath.Base(d)
			if b != "mg_api" && !strings.HasPrefix(b, "mg_engine_") {
				mg++
			}
		}
	}
	out = append(out, counter{"Minihry", fmt.Sprint(mg), "100"})
	cities, landmarks := 0, 0
	cityDirs, _ := filepath.Glob(filepath.Join(root, "content", "cities", "*", "city.yaml"))
	lock, _ := os.ReadFile(filepath.Join(root, "packs.lock"))
	for _, c := range cityDirs {
		id := filepath.Base(filepath.Dir(c))
		if _, err := os.Stat(filepath.Join(root, "build", "packs", id, "manifest.pb")); err == nil || bytes.Contains(lock, []byte("  "+id+":")) {
			cities++
		}
		if b, err := os.ReadFile(filepath.Join(filepath.Dir(c), "landmarks.yaml")); err == nil {
			var l struct {
				Landmarks []any `yaml:"landmarks"`
			}
			if yaml.Unmarshal(b, &l) == nil {
				landmarks += len(l.Landmarks)
			}
		}
	}
	out = append(out, counter{"Města (s balíčkem)", fmt.Sprint(cities), "10"})
	cars, _ := filepath.Glob(filepath.Join(root, "content", "cars", "*.json"))
	out = append(out, counter{"Auta", fmt.Sprint(len(cars)), "200"})
	out = append(out, counter{"Památky", fmt.Sprint(landmarks), "25–40 na město"})
	skits := 0
	_ = filepath.WalkDir(filepath.Join(root, "content", "dialogues"), func(p string, e os.DirEntry, err error) error {
		if err != nil || e.IsDir() || !strings.HasSuffix(p, ".json") {
			return nil
		}
		b, _ := os.ReadFile(p)
		var v struct {
			Skits []any `json:"skits"`
		}
		if json.Unmarshal(b, &v) == nil {
			skits += len(v.Skits)
		}
		return nil
	})
	out = append(out, counter{"Skity", fmt.Sprint(skits), "392"})
	t := f.Counters.Tests
	tv := "neměřeno"
	if t.Measured != nil {
		tv = fmt.Sprintf("%d / %d prochází (%s)", t.Passing, t.Total, *t.Measured)
	}
	out = append(out, counter{"Testy", tv, "vše prochází"})
	devs := make([]string, 0, len(f.Counters.FPS))
	for d := range f.Counters.FPS {
		devs = append(devs, d)
	}
	sort.Strings(devs)
	for _, d := range devs {
		v := f.Counters.FPS[d]
		s := func(x *float64) string {
			if x == nil {
				return "—"
			}
			return fmt.Sprintf("%.0f", *x)
		}
		m := "neměřeno"
		if v.Measured != nil {
			m = *v.Measured
		}
		out = append(out, counter{"FPS " + d, fmt.Sprintf("aplikace %s, web %s (%s)", s(v.App), s(v.Web), m), "60"})
	}
	return out
}

const rules = `## Pravidla (platí pro každou session)

1. Zdroj pravdy je ` + "`plans/progress.yaml`" + `. Jedna položka = jeden bod rozsahu nebo jedno akceptační kritérium
   z METROPOLE_PLAN kap. 15 (M0, M1) a METROPOLE_DUALSTACK_PLAN kap. 10 (D0–D3). Pole: id, milník, název,
   velikost (S = 1, M = 2, L = 4 body; určí se jednou a už se nemění), stav, zahájeno, hotovo, commit, důkaz.
2. Stavy: todo | wip | hotovo | čeká na Ol1na | ověřeno.
   - **hotovo** = existuje důkaz, který jde spustit (test, ` + "`citypack validate`" + `, naměřené fps). Bez důkazu ne.
   - **čeká na Ol1na** = kód je hotový, ale kritérium vyžaduje Ol1novo vyzkoušení nebo rozhodnutí.
   - **ověřeno** nastavuje jen Ol1n.
3. Po každé dokončené položce aktualizuj progress.yaml a přegeneruj tento soubor: ` + "`run/bin/metro progress`" + `
   (s ` + "`--tests`" + ` spustí všechny testy a zapíše jejich počet).
4. Položka vrácená z hotovo/ověřeno zpět do práce dostane záznam do ` + "`reopened`" + ` (regrese).
5. Na konci každé session připiš řádek do ` + "`plans/progress.log`" + `: datum, délka session, co přibylo.
6. Neměří se řádky kódu ani počet commitů.
7. Odhad dokončení milníku: rozmezí podle nejrychlejšího a nejpomalejšího třídenního okna; dokud není
   aspoň 5 hotových položek, neuvádí se.
`

func dur(d time.Duration) string {
	switch {
	case d < time.Hour:
		return fmt.Sprintf("%d min", int(d.Minutes()))
	case d < 48*time.Hour:
		return fmt.Sprintf("%.1f h", d.Hours())
	default:
		return fmt.Sprintf("%.0f dní", d.Hours()/24)
	}
}

// Render writes plans/PROGRESS.md for the moment now.
func Render(root string, f *File, now time.Time) (string, error) {
	var b strings.Builder
	b.WriteString("# Postup\n\nGENERATED by `metro progress` from plans/progress.yaml. Do not edit; edit the YAML.\n")
	fmt.Fprintf(&b, "Stav k %s.\n\n", now.Format("2006-01-02 15:04"))
	b.WriteString(rules)

	b.WriteString("\n## Milníky\n\n| Milník | Hotovo (body) | Čeká na Ol1na | Rozpracováno | Zbývá | Položky hotovo / celkem |\n|---|---|---|---|---|---|\n")
	current := ""
	for _, m := range f.Milestones {
		total, done, wait, wip, left, n, nDone := 0, 0, 0, 0, 0, 0, 0
		for _, it := range f.Items {
			if it.Milestone != m {
				continue
			}
			p := it.Points()
			total += p
			n++
			switch {
			case it.Finished():
				done += p
				nDone++
			case it.Status == Ceka:
				wait += p
			case it.Status == Wip:
				wip += p
				left += p
			default:
				left += p
			}
		}
		if current == "" && left > 0 {
			current = m
		}
		fmt.Fprintf(&b, "| %s | %d / %d | %d | %d | %d | %d / %d |\n", m, done, total, wait, wip, left, nDone, n)
	}

	b.WriteString("\n## Čeká na Ol1na\n\n")
	var waiting []Item
	for _, it := range f.Items {
		if it.Status == Ceka {
			waiting = append(waiting, it)
		}
	}
	sort.Slice(waiting, func(i, j int) bool { return waiting[i].Done < waiting[j].Done })
	if len(waiting) == 0 {
		b.WriteString("Nic.\n")
	} else {
		b.WriteString("| Položka | Čeká | Co je potřeba |\n|---|---|---|\n")
		for _, it := range waiting {
			fmt.Fprintf(&b, "| %s %s | %s | %s |\n", it.ID, it.Name, dur(now.Sub(parse(it.Done))), it.Evidence)
		}
	}

	b.WriteString("\n## Tempo\n\nBody dodaných položek (hotovo, čeká na Ol1na, ověřeno) podle dne dokončení.\n\n| Den | Body |\n|---|---|\n")
	daily := DailyPoints(f.Items)
	sum7 := 0
	for k := 6; k >= 0; k-- {
		d := day(now).AddDate(0, 0, -k)
		sum7 += daily[d]
		fmt.Fprintf(&b, "| %s | %d |\n", d.Format("2006-01-02"), daily[d])
	}
	fmt.Fprintf(&b, "\nPrůměr za posledních 7 dní: **%.1f bodu/den**.\n", float64(sum7)/7)

	b.WriteString("\n## Odhad dokončení\n\n")
	delivered := 0
	for _, it := range f.Items {
		if it.Delivered() {
			delivered++
		}
	}
	switch {
	case delivered < 5:
		fmt.Fprintf(&b, "Neuvádí se: hotových položek je %d, potřeba aspoň 5.\n", delivered)
	case current == "":
		b.WriteString("Všechny milníky mají práci hotovou nebo čekají na Ol1na.\n")
	default:
		left := 0
		for _, it := range f.Items {
			if it.Milestone == current && !it.Delivered() {
				left += it.Points()
			}
		}
		fast, slow, ok := WindowRates(daily, now)
		if !ok {
			b.WriteString("Neuvádí se: zatím žádné dodané body.\n")
			break
		}
		from := now.Add(time.Duration(float64(left)/fast*24) * time.Hour)
		to := now.Add(time.Duration(float64(left)/slow*24) * time.Hour)
		fmt.Fprintf(&b, "Aktuální milník **%s**: zbývá %d bodů (bez položek čekajících na Ol1na).\n", current, left)
		fmt.Fprintf(&b, "Při nejrychlejším třídenním okně (%.1f b/den) **%s**, při nejpomalejším (%.1f b/den) **%s**.\n",
			fast, from.Format("2006-01-02"), slow, to.Format("2006-01-02"))
		b.WriteString("Měřeno na krátké historii; rozmezí se zpřesní s každým dalším dnem.\n")
	}

	b.WriteString("\n## Obsah\n\n| Co | Stav | Cíl |\n|---|---|---|\n")
	for _, c := range countContent(root, f) {
		fmt.Fprintf(&b, "| %s | %s | %s |\n", c.name, c.value, c.target)
	}

	b.WriteString("\n## Znovuotevřené položky (regrese)\n\n")
	any := false
	for _, it := range f.Items {
		for _, r := range it.Reopened {
			fmt.Fprintf(&b, "- %s %s – %s: %s\n", it.ID, it.Name, r.Date, r.Reason)
			any = true
		}
	}
	if !any {
		b.WriteString("Žádné.\n")
	}
	return b.String(), nil
}

// RunTests runs every suite and returns (total, passing).
func RunTests(root string) (int, int, error) {
	total, pass := 0, 0
	add := func(t, p int) { total += t; pass += p }
	for _, dir := range []string{"tools/metro", "tools/citypack"} {
		t, p, err := goTests(filepath.Join(root, dir))
		if err != nil {
			return 0, 0, err
		}
		add(t, p)
	}
	for _, dir := range []string{"packages/rules_core", "packages/world_engine", "packages/drive_core", "app"} {
		t, p, err := flutterTests(filepath.Join(root, dir))
		if err != nil {
			return 0, 0, err
		}
		add(t, p)
	}
	t, p, err := vitest(filepath.Join(root, "web"))
	if err != nil {
		return 0, 0, err
	}
	add(t, p)
	return total, pass, nil
}

func goTests(dir string) (int, int, error) {
	cmd := exec.Command("go", "test", "-json", "-count=1", "./...")
	cmd.Dir = dir
	out, _ := cmd.Output() // a failing test exits non-zero; count it instead
	total, pass := 0, 0
	sc := bufio.NewScanner(bytes.NewReader(out))
	sc.Buffer(make([]byte, 1<<20), 1<<24)
	for sc.Scan() {
		var ev struct{ Action, Test string }
		if json.Unmarshal(sc.Bytes(), &ev) != nil || ev.Test == "" || strings.Contains(ev.Test, "/") {
			continue
		}
		switch ev.Action {
		case "pass":
			total++
			pass++
		case "fail":
			total++
		}
	}
	if total == 0 {
		return 0, 0, fmt.Errorf("go test in %s reported no tests", dir)
	}
	return total, pass, nil
}

func flutterTests(dir string) (int, int, error) {
	cmd := exec.Command("flutter", "test", "--reporter", "json")
	cmd.Dir = dir
	out, _ := cmd.Output()
	total, pass := 0, 0
	sc := bufio.NewScanner(bytes.NewReader(out))
	sc.Buffer(make([]byte, 1<<20), 1<<24)
	for sc.Scan() {
		var ev struct {
			Type    string `json:"type"`
			Result  string `json:"result"`
			Hidden  bool   `json:"hidden"`
			Skipped bool   `json:"skipped"`
		}
		if json.Unmarshal(sc.Bytes(), &ev) != nil || ev.Type != "testDone" || ev.Hidden || ev.Skipped {
			continue
		}
		total++
		if ev.Result == "success" {
			pass++
		}
	}
	if total == 0 {
		return 0, 0, fmt.Errorf("flutter test in %s reported no tests", dir)
	}
	return total, pass, nil
}

func vitest(dir string) (int, int, error) {
	tmp, err := os.CreateTemp("", "metro-vitest-*.json")
	if err != nil {
		return 0, 0, err
	}
	tmp.Close()
	defer os.Remove(tmp.Name())
	cmd := exec.Command("npx", "vitest", "run", "--reporter=json", "--outputFile="+tmp.Name())
	cmd.Dir = dir
	_ = cmd.Run() // failing tests still write the report
	out, err := os.ReadFile(tmp.Name())
	if err != nil {
		return 0, 0, err
	}
	var r struct {
		NumTotalTests   int `json:"numTotalTests"`
		NumPassedTests  int `json:"numPassedTests"`
		NumPendingTests int `json:"numPendingTests"`
	}
	if err := json.Unmarshal(out, &r); err != nil || r.NumTotalTests == 0 {
		return 0, 0, fmt.Errorf("vitest in %s: unreadable report", dir)
	}
	return r.NumTotalTests - r.NumPendingTests, r.NumPassedTests, nil
}

// SetTests writes counters.tests into progress.yaml, keeping comments and layout.
func SetTests(root string, total, passing int, now time.Time) error {
	p := filepath.Join(root, Path)
	b, err := os.ReadFile(p)
	if err != nil {
		return err
	}
	re := regexp.MustCompile(`(?m)^  tests: \{[^}]*\}`)
	if !re.Match(b) {
		return fmt.Errorf("%s: counters.tests line not found", Path)
	}
	line := fmt.Sprintf("  tests: {total: %d, passing: %d, measured: %s}", total, passing, now.Format(timeFmt))
	return os.WriteFile(p, re.ReplaceAll(b, []byte(line)), 0o644)
}
