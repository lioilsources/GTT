// Package npc loads the NPC dialogue content (content/npc, specs/dialogue.md), checks the
// references the JSON Schema cannot express and merges it into the runtime NpcPack.
package npc

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"

	"metro/internal/repo"
)

// Pack is the merged content written to content/npc.json (schema NpcPack).
type Pack struct {
	Characters []map[string]any `json:"characters"`
	Skits      []map[string]any `json:"skits"`
}

// Load reads characters.yaml and every skits/*.yaml; skits are sorted by id.
func Load(root string) (*Pack, error) {
	var chars struct {
		Characters []map[string]any `yaml:"characters"`
	}
	if err := readYAML(filepath.Join(root, repo.NpcCharacters), &chars); err != nil {
		return nil, err
	}
	p := &Pack{Characters: chars.Characters, Skits: []map[string]any{}}
	files, err := filepath.Glob(filepath.Join(root, repo.NpcSkits, "*.yaml"))
	if err != nil {
		return nil, err
	}
	for _, f := range files {
		var s map[string]any
		if err := readYAML(f, &s); err != nil {
			return nil, err
		}
		p.Skits = append(p.Skits, s)
	}
	sort.Slice(p.Skits, func(i, j int) bool { return str(p.Skits[i], "id") < str(p.Skits[j], "id") })
	return p, nil
}

// Check returns cross-reference errors: skit id = file name, known character, unique ids,
// portrait index inside design tokens color.npc.portraits.
func Check(root string) []error {
	p, err := Load(root)
	if err != nil {
		return []error{err}
	}
	var errs []error
	portraits, err := portraitCount(root)
	if err != nil {
		errs = append(errs, err)
	}
	chars := map[string]bool{}
	for _, c := range p.Characters {
		id := str(c, "id")
		if chars[id] {
			errs = append(errs, fmt.Errorf("%s: duplicate character %s", repo.NpcCharacters, id))
		}
		chars[id] = true
		if n, ok := c["portrait"].(int); ok && n >= portraits {
			errs = append(errs, fmt.Errorf("%s: %s portrait %d, design tokens have %d", repo.NpcCharacters, id, n, portraits))
		}
	}
	files, _ := filepath.Glob(filepath.Join(root, repo.NpcSkits, "*.yaml"))
	for _, f := range files {
		var s map[string]any
		if err := readYAML(f, &s); err != nil {
			errs = append(errs, err)
			continue
		}
		rel, _ := filepath.Rel(root, f)
		if id := str(s, "id"); id != strings.TrimSuffix(filepath.Base(f), ".yaml") {
			errs = append(errs, fmt.Errorf("%s: id %q must match the file name", rel, id))
		}
		if c := str(s, "character"); !chars[c] {
			errs = append(errs, fmt.Errorf("%s: unknown character %q", rel, c))
		}
	}
	return errs
}

// JSON is the merged pack as indented JSON.
func (p *Pack) JSON() ([]byte, error) {
	b, err := json.MarshalIndent(p, "", " ")
	if err != nil {
		return nil, err
	}
	return append(b, '\n'), nil
}

func portraitCount(root string) (int, error) {
	b, err := os.ReadFile(filepath.Join(root, repo.Tokens))
	if err != nil {
		return 0, err
	}
	var t struct {
		Color struct {
			Npc struct {
				Portraits []string `json:"portraits"`
			} `json:"npc"`
		} `json:"color"`
	}
	if err := json.Unmarshal(b, &t); err != nil {
		return 0, err
	}
	if len(t.Color.Npc.Portraits) == 0 {
		return 0, fmt.Errorf("%s: color.npc.portraits is missing", repo.Tokens)
	}
	return len(t.Color.Npc.Portraits), nil
}

func str(m map[string]any, k string) string {
	s, _ := m[k].(string)
	return s
}

func readYAML(path string, v any) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if err := yaml.Unmarshal(b, v); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	return nil
}
