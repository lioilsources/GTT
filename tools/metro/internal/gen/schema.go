package gen

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// TypeSchemas are the schema files whose types both clients use.
var TypeSchemas = []string{"car.schema.json", "minigame.schema.json", "save.schema.json"}

type jsProp struct {
	Type                 any                `json:"type"`
	Enum                 []any              `json:"enum"`
	Const                any                `json:"const"`
	Ref                  string             `json:"$ref"`
	Items                *jsProp            `json:"items"`
	AdditionalProperties json.RawMessage    `json:"additionalProperties"`
	Properties           map[string]*jsProp `json:"properties"`
	Required             []string           `json:"required"`
	Description          string             `json:"description"`
	Title                string             `json:"title"`
	Defs                 map[string]*jsProp `json:"$defs"`
	order                []string
}

type sType struct {
	name   string
	doc    string
	schema *jsProp
}

// propOrder returns property names in file order (encoding/json maps lose it).
func propOrder(raw []byte, path ...string) ([]string, error) {
	var root map[string]json.RawMessage
	if err := json.Unmarshal(raw, &root); err != nil {
		return nil, err
	}
	cur := raw
	for _, p := range path {
		var m map[string]json.RawMessage
		if err := json.Unmarshal(cur, &m); err != nil {
			return nil, err
		}
		cur = m[p]
	}
	dec := json.NewDecoder(strings.NewReader(string(cur)))
	if _, err := dec.Token(); err != nil {
		return nil, err
	}
	var keys []string
	for dec.More() {
		t, err := dec.Token()
		if err != nil {
			return nil, err
		}
		keys = append(keys, t.(string))
		var skip json.RawMessage
		if err := dec.Decode(&skip); err != nil {
			return nil, err
		}
	}
	return keys, nil
}

func loadSchemaTypes(root, dir string) ([]sType, error) {
	var out []sType
	for _, f := range TypeSchemas {
		raw, err := os.ReadFile(filepath.Join(root, dir, f))
		if err != nil {
			return nil, err
		}
		var s jsProp
		if err := json.Unmarshal(raw, &s); err != nil {
			return nil, fmt.Errorf("%s: %w", f, err)
		}
		if s.Properties != nil {
			o, err := propOrder(raw, "properties")
			if err != nil {
				return nil, err
			}
			s.order = o
			out = append(out, sType{name: s.Title, doc: s.Description, schema: &s})
		}
		names := make([]string, 0, len(s.Defs))
		for n := range s.Defs {
			names = append(names, n)
		}
		sort.Strings(names)
		for _, n := range names {
			d := s.Defs[n]
			o, err := propOrder(raw, "$defs", n, "properties")
			if err != nil {
				return nil, err
			}
			d.order = o
			out = append(out, sType{name: n, doc: d.Description, schema: d})
		}
	}
	return out, nil
}

func refName(ref string) string { return ref[strings.LastIndex(ref, "/")+1:] }

func (p *jsProp) typeName() string {
	if s, ok := p.Type.(string); ok {
		return s
	}
	if len(p.Enum) > 0 {
		return "string"
	}
	if p.Const != nil {
		switch p.Const.(type) {
		case float64:
			return "integer"
		case string:
			return "string"
		}
	}
	return ""
}

func (p *jsProp) mapValue() *jsProp {
	if len(p.AdditionalProperties) == 0 || string(p.AdditionalProperties) == "false" {
		return nil
	}
	var v jsProp
	if err := json.Unmarshal(p.AdditionalProperties, &v); err != nil {
		return nil
	}
	return &v
}

// dartField returns the Dart type, a JSON read expression and a JSON write expression.
func dartField(p *jsProp, name, key string) (string, string, string, error) {
	j := fmt.Sprintf("j['%s']", key)
	if p.Ref != "" {
		t := refName(p.Ref)
		return t, fmt.Sprintf("%s.fromJson(_map(%s, '%s'))", t, j, key), name + ".toJson()", nil
	}
	switch p.typeName() {
	case "string":
		check := ""
		if len(p.Enum) > 0 {
			var vals []string
			for _, e := range p.Enum {
				vals = append(vals, fmt.Sprintf("'%v'", e))
			}
			check = fmt.Sprintf(", const [%s]", strings.Join(vals, ", "))
		}
		return "String", fmt.Sprintf("_str(%s, '%s'%s)", j, key, check), name, nil
	case "integer":
		return "int", fmt.Sprintf("_int(%s, '%s')", j, key), name, nil
	case "number":
		return "double", fmt.Sprintf("_num(%s, '%s')", j, key), name, nil
	case "boolean":
		return "bool", fmt.Sprintf("_bool(%s, '%s')", j, key), name, nil
	case "array":
		et, er, ew, err := dartField(p.Items, "e", key+"[]")
		if err != nil {
			return "", "", "", err
		}
		er = strings.ReplaceAll(er, "j['"+key+"[]']", "e")
		w := name
		if ew != "e" {
			w = fmt.Sprintf("[for (final e in %s) %s]", name, ew)
		}
		return "List<" + et + ">", fmt.Sprintf("[for (final e in _list(%s, '%s')) %s]", j, key, er), w, nil
	case "object":
		if v := p.mapValue(); v != nil {
			et, er, ew, err := dartField(v, "e.value", key+"{}")
			if err != nil {
				return "", "", "", err
			}
			er = strings.ReplaceAll(er, "j['"+key+"{}']", "e.value")
			return "Map<String, " + et + ">", fmt.Sprintf("{for (final e in _map(%s, '%s').entries) e.key: %s}", j, key, er),
				fmt.Sprintf("{for (final e in %s.entries) e.key: %s}", name, ew), nil
		}
		return "Map<String, Object?>", fmt.Sprintf("_map(%s, '%s')", j, key), name, nil
	}
	return "", "", "", fmt.Errorf("unsupported schema type for %s", key)
}

func tsField(p *jsProp) (string, error) {
	if p.Ref != "" {
		return refName(p.Ref), nil
	}
	switch p.typeName() {
	case "string":
		if len(p.Enum) > 0 {
			var vals []string
			for _, e := range p.Enum {
				vals = append(vals, fmt.Sprintf("'%v'", e))
			}
			return strings.Join(vals, " | "), nil
		}
		return "string", nil
	case "integer", "number":
		return "number", nil
	case "boolean":
		return "boolean", nil
	case "array":
		t, err := tsField(p.Items)
		if strings.Contains(t, "|") {
			t = "(" + t + ")"
		}
		return t + "[]", err
	case "object":
		if v := p.mapValue(); v != nil {
			t, err := tsField(v)
			return "Record<string, " + t + ">", err
		}
		return "Record<string, unknown>", nil
	}
	return "", fmt.Errorf("unsupported schema type")
}

const dartSchemaHelpers = `
Never _bad(String key, String what) => throw FormatException('$key must be $what');

Object? _req(Object? v, String key) => v ?? (throw FormatException('missing $key'));

String _str(Object? v, String key, [List<String>? allowed]) {
  final s = _req(v, key);
  if (s is! String) _bad(key, 'a string');
  if (allowed != null && !allowed.contains(s)) _bad(key, 'one of $allowed');
  return s;
}

int _int(Object? v, String key) {
  final x = _req(v, key);
  return x is int ? x : _bad(key, 'an integer');
}

double _num(Object? v, String key) {
  final x = _req(v, key);
  return x is num ? x.toDouble() : _bad(key, 'a number');
}

bool _bool(Object? v, String key) {
  final x = _req(v, key);
  return x is bool ? x : _bad(key, 'a boolean');
}

List<Object?> _list(Object? v, String key) {
  final x = _req(v, key);
  return x is List ? x : _bad(key, 'a list');
}

Map<String, Object?> _map(Object? v, String key) {
  final x = _req(v, key);
  return x is Map ? x.cast<String, Object?>() : _bad(key, 'an object');
}
`

// Schema generates Dart classes and TS interfaces for TypeSchemas.
func Schema(o *Output, dir string) error {
	types, err := loadSchemaTypes(o.Root, dir)
	if err != nil {
		return err
	}
	var d, ts strings.Builder
	d.WriteString(Header("//", dir+"/{"+strings.Join(TypeSchemas, ",")+"}"))
	d.WriteString(dartSchemaHelpers)
	ts.WriteString(Header("//", dir+"/{"+strings.Join(TypeSchemas, ",")+"}"))
	for _, t := range types {
		req := map[string]bool{}
		for _, r := range t.schema.Required {
			req[r] = true
		}
		var fields []string
		var reads, writes []string
		var tsFields []string
		for _, key := range t.schema.order {
			p := t.schema.Properties[key]
			name := Field(key)
			dt, dr, dw, err := dartField(p, name, key)
			if err != nil {
				return fmt.Errorf("%s.%s: %w", t.name, key, err)
			}
			tt, err := tsField(p)
			if err != nil {
				return fmt.Errorf("%s.%s: %w", t.name, key, err)
			}
			opt := ""
			if !req[key] {
				opt = "?"
				dr = fmt.Sprintf("j['%s'] == null ? null : %s", key, dr)
				if dw != name {
					dw = strings.Replace(dw, name, name+"!", 1)
					dw = fmt.Sprintf("if (%s != null) '%s': %s", name, key, dw)
				} else {
					dw = fmt.Sprintf("if (%s != null) '%s': %s", name, key, dw)
				}
			} else {
				dw = fmt.Sprintf("'%s': %s", key, dw)
			}
			fields = append(fields, Doc("  ", p.Description)+fmt.Sprintf("  %s%s %s;\n", dt, opt, name))
			reads = append(reads, fmt.Sprintf("        %s: %s,\n", name, dr))
			writes = append(writes, "        "+dw+",\n")
			tsFields = append(tsFields, TSDoc("  ", p.Description)+fmt.Sprintf("  %s%s: %s;\n", key, opt, tt))
		}
		fmt.Fprintf(&d, "\n%sclass %s {\n  %s({\n", Doc("", t.doc), t.name, t.name)
		for _, key := range t.schema.order {
			r := "required "
			if !req[key] {
				r = ""
			}
			fmt.Fprintf(&d, "    %sthis.%s,\n", r, Field(key))
		}
		fmt.Fprintf(&d, "  });\n\n  factory %s.fromJson(Map<String, Object?> j) => %s(\n%s      );\n\n", t.name, t.name, strings.Join(reads, ""))
		d.WriteString(strings.Join(fields, ""))
		fmt.Fprintf(&d, "\n  Map<String, Object?> toJson() => {\n%s      };\n}\n", strings.Join(writes, ""))
		fmt.Fprintf(&ts, "\n%sexport interface %s {\n%s}\n", TSDoc("", t.doc), t.name, strings.Join(tsFields, ""))
	}
	o.Add("packages/shared_gen/lib/src/schema.g.dart", []byte(d.String()))
	o.Add("web/src/gen/schema.ts", []byte(ts.String()))
	return nil
}
