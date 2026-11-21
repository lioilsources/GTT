package gen

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

type idEnum struct {
	name, doc, source string
	values            []string
	labels            map[string]string // optional display name per id (cities)
}

// Ids generates enums for cities, cars, minigame engines and minigames.
func Ids(o *Output, citiesDir, carsDir, catalog string) error {
	var enums []idEnum

	dirs, err := os.ReadDir(filepath.Join(o.Root, citiesDir))
	if err != nil {
		return err
	}
	cities := idEnum{name: "CityId", doc: "Cities with a content/cities/<id>/city.yaml.", source: citiesDir, labels: map[string]string{}}
	for _, d := range dirs {
		b, err := os.ReadFile(filepath.Join(o.Root, citiesDir, d.Name(), "city.yaml"))
		if err != nil {
			continue
		}
		var c struct {
			Name string `yaml:"name"`
		}
		if err := yaml.Unmarshal(b, &c); err != nil {
			return fmt.Errorf("%s/city.yaml: %w", d.Name(), err)
		}
		cities.values = append(cities.values, d.Name())
		cities.labels[d.Name()] = c.Name
	}
	enums = append(enums, cities)

	cars := idEnum{name: "CarId", doc: "Cars defined in content/cars/<id>.json.", source: carsDir}
	files, err := filepath.Glob(filepath.Join(o.Root, carsDir, "*.json"))
	if err != nil {
		return err
	}
	for _, f := range files {
		cars.values = append(cars.values, strings.TrimSuffix(filepath.Base(f), ".json"))
	}
	enums = append(enums, cars)

	b, err := os.ReadFile(filepath.Join(o.Root, catalog))
	if err != nil {
		return err
	}
	var cat struct {
		Engines   []string `yaml:"engines"`
		Minigames []struct {
			ID     string `yaml:"id"`
			Engine string `yaml:"engine"`
		} `yaml:"minigames"`
	}
	if err := yaml.Unmarshal(b, &cat); err != nil {
		return fmt.Errorf("%s: %w", catalog, err)
	}
	engines := map[string]bool{}
	for _, e := range cat.Engines {
		engines[e] = true
	}
	mg := idEnum{name: "MinigameId", doc: "Minigames in content/minigames/catalog.yaml.", source: catalog}
	for _, m := range cat.Minigames {
		if !engines[m.Engine] {
			return fmt.Errorf("%s: minigame %s uses unknown engine %s", catalog, m.ID, m.Engine)
		}
		mg.values = append(mg.values, m.ID)
	}
	enums = append(enums, idEnum{name: "EngineId", doc: "Minigame engines (METROPOLE_PLAN 9.3).", source: catalog, values: cat.Engines}, mg)

	var d, ts strings.Builder
	d.WriteString(Header("//", citiesDir+", "+carsDir+", "+catalog))
	ts.WriteString(Header("//", citiesDir+", "+carsDir+", "+catalog))
	for _, e := range enums {
		vals := append([]string{}, e.values...)
		if e.name != "EngineId" && e.name != "MinigameId" {
			sort.Strings(vals)
		}
		fmt.Fprintf(&d, "\n%senum %s {\n", Doc("", e.doc), e.name)
		for _, v := range vals {
			if e.labels != nil {
				fmt.Fprintf(&d, "  %s('%s', %s),\n", Camel(v), v, jsonStr(e.labels[v]))
			} else {
				fmt.Fprintf(&d, "  %s('%s'),\n", Camel(v), v)
			}
		}
		if e.labels != nil {
			fmt.Fprintf(&d, "  ;\n\n  const %s(this.id, this.name);\n\n  /// The id as written in content files.\n  final String id;\n\n  /// Display name from city.yaml (a proper noun, not translated).\n  final String name;\n\n", e.name)
		} else {
			fmt.Fprintf(&d, "  ;\n\n  const %s(this.id);\n\n  /// The id as written in content files.\n  final String id;\n\n", e.name)
		}
		fmt.Fprintf(&d, "  static %s? byId(String id) {\n    for (final v in values) {\n      if (v.id == id) return v;\n    }\n    return null;\n  }\n}\n", e.name)

		q := make([]string, len(vals))
		for i, v := range vals {
			q[i] = "'" + v + "'"
		}
		fmt.Fprintf(&ts, "\n%sexport const %sValues = [%s] as const;\nexport type %s = (typeof %sValues)[number];\n",
			TSDoc("", e.doc), lowerFirst(e.name), strings.Join(q, ", "), e.name, lowerFirst(e.name))
		if e.labels != nil {
			fmt.Fprintf(&ts, "export const %sNames: Record<%s, string> = {\n", lowerFirst(e.name), e.name)
			for _, v := range vals {
				fmt.Fprintf(&ts, "  %s: %s,\n", v, jsonStr(e.labels[v]))
			}
			ts.WriteString("};\n")
		}
	}
	o.Add("packages/shared_gen/lib/src/ids.g.dart", []byte(d.String()))
	o.Add("web/src/gen/ids.ts", []byte(ts.String()))
	return nil
}
