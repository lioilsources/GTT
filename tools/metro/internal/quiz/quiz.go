// Package quiz loads the city quiz banks (content/quiz/<city>.yaml, specs/minigames/kviz.md),
// checks them and turns them into JSON for both clients.
package quiz

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

// Text is one string in every UI language.
type Text struct {
	En string `yaml:"en" json:"en"`
	Cs string `yaml:"cs" json:"cs"`
}

// Options are the four answers in every UI language, in file order.
type Options struct {
	En []string `yaml:"en" json:"en"`
	Cs []string `yaml:"cs" json:"cs"`
}

// Question is one bank entry; Answer indexes Options.
type Question struct {
	ID      string  `yaml:"id" json:"id"`
	Q       Text    `yaml:"q" json:"q"`
	Options Options `yaml:"options" json:"options"`
	Answer  int     `yaml:"answer" json:"answer"`
}

// Bank is one city's questions in file order.
type Bank struct {
	Questions []Question `yaml:"questions" json:"questions"`
}

// Load reads every <city>.yaml under dir and checks it. A missing dir is no banks.
func Load(dir string) (map[string]Bank, error) {
	files, _ := filepath.Glob(filepath.Join(dir, "*.yaml"))
	sort.Strings(files)
	out := map[string]Bank{}
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			return nil, err
		}
		var bank Bank
		if err := yaml.Unmarshal(b, &bank); err != nil {
			return nil, fmt.Errorf("%s: %w", f, err)
		}
		if err := Check(bank); err != nil {
			return nil, fmt.Errorf("%s: %w", f, err)
		}
		out[strings.TrimSuffix(filepath.Base(f), ".yaml")] = bank
	}
	return out, nil
}

// Check enforces the bank rules of specs/minigames/kviz.md.
func Check(bank Bank) error {
	seen := map[string]bool{}
	for i, q := range bank.Questions {
		where := fmt.Sprintf("question %d (%s)", i, q.ID)
		switch {
		case q.ID == "":
			return fmt.Errorf("%s: missing id", where)
		case seen[q.ID]:
			return fmt.Errorf("%s: duplicate id", where)
		case q.Q.En == "" || q.Q.Cs == "":
			return fmt.Errorf("%s: question needs en and cs", where)
		case len(q.Options.En) != 4 || len(q.Options.Cs) != 4:
			return fmt.Errorf("%s: needs exactly 4 options in en and cs", where)
		case q.Answer < 0 || q.Answer > 3:
			return fmt.Errorf("%s: answer must be 0-3", where)
		}
		for _, o := range append(append([]string{}, q.Options.En...), q.Options.Cs...) {
			if o == "" {
				return fmt.Errorf("%s: empty option", where)
			}
		}
		seen[q.ID] = true
	}
	return nil
}
