package gen

import (
	"fmt"
	"metro/internal/repo"
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
	// specs/cities.md "Výchozí město": the first city of bundle_cities is the start city, and the
	// clients take it as CityId's first value. Bundled cities go first in metro.yaml order, the
	// rest follow by name.
	var guard struct {
		BundleCities []string `yaml:"bundle_cities"`
	}
	if b, err := os.ReadFile(filepath.Join(o.Root, repo.GuardConfig)); err == nil {
		if err := yaml.Unmarshal(b, &guard); err != nil {
			return fmt.Errorf("metro.yaml: %w", err)
		}
	}
	rank := map[string]int{}
	for i, c := range guard.BundleCities {
		rank[c] = i + 1
	}
	sort.SliceStable(cities.values, func(i, j int) bool {
		ri, rj := rank[cities.values[i]], rank[cities.values[j]]
		if ri == 0 || rj == 0 {
			if ri != rj {
				return ri != 0
			}
			return cities.values[i] < cities.values[j]
		}
		return ri < rj
	})
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
			ID         string   `yaml:"id"`
			Engine     string   `yaml:"engine"`
			TargetMin  int      `yaml:"target_min"`
			Cities     []string `yaml:"cities"`
			CasinoLike bool     `yaml:"casino_like"`
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
	d.WriteString("\nimport 'schema.g.dart';\n")
	ts.WriteString(Header("//", citiesDir+", "+carsDir+", "+catalog))
	ts.WriteString("\nimport type { MinigameMeta } from './schema';\n")
	for _, e := range enums {
		vals := append([]string{}, e.values...)
		if e.name != "EngineId" && e.name != "MinigameId" && e.name != "CityId" {
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
	// Catalog metadata per minigame (the MinigameMeta of the contract, DUALSTACK 6.5).
	d.WriteString("\n/// Contract metadata of every minigame in content/minigames/catalog.yaml.\nfinal Map<MinigameId, MinigameMeta> minigameCatalog = {\n")
	ts.WriteString("\n/** Contract metadata of every minigame in content/minigames/catalog.yaml. */\nexport const minigameCatalog: Record<MinigameId, MinigameMeta> = {\n")
	for _, m := range cat.Minigames {
		dc := make([]string, len(m.Cities))
		for i, c := range m.Cities {
			dc[i] = "'" + c + "'"
		}
		cities := strings.Join(dc, ", ")
		fmt.Fprintf(&d, "  MinigameId.%s: MinigameMeta(id: '%s', engine: '%s', targetLengthS: %d, cities: [%s], casinoLike: %t),\n",
			Camel(m.ID), m.ID, m.Engine, m.TargetMin*60, cities, m.CasinoLike)
		fmt.Fprintf(&ts, "  %s: { id: '%s', engine: '%s', targetLengthS: %d, cities: [%s], casinoLike: %t },\n",
			m.ID, m.ID, m.Engine, m.TargetMin*60, cities, m.CasinoLike)
	}
	d.WriteString("};\n")
	ts.WriteString("};\n")
	o.Add("packages/shared_gen/lib/src/ids.g.dart", []byte(d.String()))
	o.Add("web/src/gen/ids.ts", []byte(ts.String()))
	return nil
}
