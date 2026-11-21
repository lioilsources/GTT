// Package validate checks shared content against the JSON Schemas in schema/.
package validate

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/santhosh-tekuri/jsonschema/v6"
	"gopkg.in/yaml.v3"

	"metro/internal/npc"
	"metro/internal/repo"
)

// Target is a set of instance files checked against one schema.
type Target struct {
	Schema string
	Glob   string
}

var Targets = []Target{
	{"car.schema.json", repo.Cars + "/*.json"},
	{"parity.schema.json", repo.Parity},
	{"vector.schema.json", repo.Vectors + "/*.json"},
	{"scenario.schema.json", repo.Scenarios + "/*/*.json"},
	{"bench.schema.json", repo.Bench + "/*.json"},
	{"npc.schema.json#/$defs/NpcCharacters", repo.NpcCharacters},
	{"npc.schema.json#/$defs/NpcSkit", repo.NpcSkits + "/*.yaml"},
}

// Load reads JSON or YAML into the generic form jsonschema expects.
func Load(path string) (any, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	if strings.HasSuffix(path, ".yaml") || strings.HasSuffix(path, ".yml") {
		var v any
		if err := yaml.Unmarshal(b, &v); err != nil {
			return nil, err
		}
		if b, err = json.Marshal(v); err != nil {
			return nil, err
		}
	}
	return jsonschema.UnmarshalJSON(bytes.NewReader(b))
}

// Run validates every target; it returns one error per invalid file.
func Run(root string, only ...string) []error {
	c := jsonschema.NewCompiler()
	var errs []error
	for _, t := range Targets {
		if len(only) > 0 && !contains(only, t.Schema) {
			continue
		}
		sch, err := c.Compile(filepath.Join(root, repo.Schema, t.Schema))
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", t.Schema, err))
			continue
		}
		files, _ := filepath.Glob(filepath.Join(root, t.Glob))
		for _, f := range files {
			rel, _ := filepath.Rel(root, f)
			inst, err := Load(f)
			if err != nil {
				errs = append(errs, fmt.Errorf("%s: %w", rel, err))
				continue
			}
			if err := sch.Validate(inst); err != nil {
				errs = append(errs, fmt.Errorf("%s: %v", rel, err))
			}
		}
	}
	if len(only) == 0 {
		errs = append(errs, npc.Check(root)...)
	}
	if len(only) == 0 || contains(only, "car.schema.json") {
		errs = append(errs, CarPaints(root)...)
	}
	return errs
}

// CarPaints checks that every car's paint names a key of color.carPaint in design/tokens.json
// (specs/cars.md: body colours live only in the tokens).
func CarPaints(root string) []error {
	var tok struct {
		Color struct {
			CarPaint map[string]any `json:"carPaint"`
		} `json:"color"`
	}
	b, err := os.ReadFile(filepath.Join(root, repo.Tokens))
	if err != nil {
		return []error{err}
	}
	if err := json.Unmarshal(b, &tok); err != nil {
		return []error{fmt.Errorf("%s: %w", repo.Tokens, err)}
	}
	var errs []error
	files, _ := filepath.Glob(filepath.Join(root, repo.Cars, "*.json"))
	for _, f := range files {
		var car struct {
			Paint string `json:"paint"`
		}
		rel, _ := filepath.Rel(root, f)
		b, err := os.ReadFile(f)
		if err == nil {
			err = json.Unmarshal(b, &car)
		}
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", rel, err))
			continue
		}
		if _, ok := tok.Color.CarPaint[car.Paint]; !ok || strings.HasPrefix(car.Paint, "$") {
			errs = append(errs, fmt.Errorf("%s: paint %q is not a key of color.carPaint in %s", rel, car.Paint, repo.Tokens))
		}
	}
	return errs
}

func contains(xs []string, x string) bool {
	for _, v := range xs {
		if v == x {
			return true
		}
	}
	return false
}
