package progress

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"gopkg.in/yaml.v3"

	"metro/internal/parity"
)

// README status block markers (Prompts/05 L-S2): metro progress rewrites everything between them.
const (
	StatusOpen  = "<!-- metro:status -->"
	StatusClose = "<!-- /metro:status -->"
)

var stampLine = regexp.MustCompile(`(?m)^_Stav k \d{4}-\d{2}-\d{2}[^\n]*_\n`)

// StatusBlock renders the README status block (including markers) for the moment now.
func StatusBlock(root string, f *File, now time.Time) (string, error) {
	rows, err := parity.Load(root)
	if err != nil {
		return "", err
	}
	c := map[string]string{}
	for _, x := range countContent(root, f) {
		c[x.name] = x.value
	}
	mgW, mgF := minigameClients(root, rows)
	both, onlyW, onlyF, none := 0, 0, 0, 0
	for _, r := range rows {
		switch w, fl := r.Web == "done", r.Flutter == "done"; {
		case w && fl:
			both++
		case w:
			onlyW++
		case fl:
			onlyF++
		default:
			none++
		}
	}
	var b strings.Builder
	b.WriteString(StatusOpen + "\n")
	b.WriteString("| | |\n|---|---|\n")
	fmt.Fprintf(&b, "| Města s balíčkem | %s |\n", c["Města (s balíčkem)"])
	fmt.Fprintf(&b, "| Minihry v katalogu | %s (web %d, Flutter %d) |\n", c["Minihry"], mgW, mgF)
	fmt.Fprintf(&b, "| Auta | %s |\n", c["Auta"])
	fmt.Fprintf(&b, "| Památky | %s |\n", c["Památky"])
	fmt.Fprintf(&b, "| Skity NPC | %s |\n", c["Skity"])
	fmt.Fprintf(&b, "| Testy | %s |\n", c["Testy"])
	fmt.Fprintf(&b, "| Funkce (`parity.yaml`) | %d v obou klientech, %d jen web, %d jen Flutter, %d rozpracováno |\n", both, onlyW, onlyF, none)
	fmt.Fprintf(&b, "\n_Stav k %s, generuje `metro progress`._\n", now.Format("2006-01-02"))
	b.WriteString(StatusClose)
	return b.String(), nil
}

// minigameClients counts catalog minigames whose parity row (spec specs/minigames/<id>.md) is
// done in the web and in the Flutter client.
func minigameClients(root string, rows []parity.Row) (web, flutter int) {
	b, err := os.ReadFile(filepath.Join(root, "content", "minigames", "catalog.yaml"))
	if err != nil {
		return 0, 0
	}
	var cat struct {
		Minigames []struct {
			ID string `yaml:"id"`
		} `yaml:"minigames"`
	}
	if yaml.Unmarshal(b, &cat) != nil {
		return 0, 0
	}
	for _, m := range cat.Minigames {
		spec := "specs/minigames/" + m.ID + ".md"
		for _, r := range rows {
			if r.Spec == spec || strings.HasPrefix(r.Spec, spec+"@") {
				if r.Web == "done" {
					web++
				}
				if r.Flutter == "done" {
					flutter++
				}
				break
			}
		}
	}
	return web, flutter
}

// ReplaceStatus swaps the status block in a README; it fails when the markers are missing.
func ReplaceStatus(readme, block string) (string, error) {
	i := strings.Index(readme, StatusOpen)
	j := strings.Index(readme, StatusClose)
	if i < 0 || j < i {
		return "", fmt.Errorf("README.md: status markers %s … %s missing", StatusOpen, StatusClose)
	}
	return readme[:i] + block + readme[j+len(StatusClose):], nil
}

// StatusStale reports whether the README block differs from block, ignoring the date line.
func StatusStale(readme, block string) (bool, error) {
	want, err := ReplaceStatus(readme, block)
	if err != nil {
		return true, err
	}
	return stampLine.ReplaceAllString(want, "") != stampLine.ReplaceAllString(readme, ""), nil
}
