package gen

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

// tKind is the type of a tuning value, read from the YAML literal.
type tKind int

const (
	kMap tKind = iota
	kInt
	kFloat
	kBool
	kString
	kIntList
	kFloatList
	kStringList
)

type tNode struct {
	key      string
	kind     tKind
	doc      string
	children []*tNode
	class    string // for maps
}

// numericMap: a map whose values are all numbers of the same kind (used by id, e.g. lanes_by_class).
func (n *tNode) numericMap() tKind {
	if n.kind != kMap || len(n.children) == 0 {
		return -1
	}
	k := n.children[0].kind
	for _, c := range n.children {
		if c.kind != k || (k != kInt && k != kFloat) {
			return -1
		}
	}
	return k
}

func comment(ns ...*yaml.Node) string {
	var parts []string
	for _, n := range ns {
		if n == nil {
			continue
		}
		for _, c := range []string{n.HeadComment, n.LineComment} {
			for _, l := range strings.Split(c, "\n") {
				l = strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(l), "#"))
				if l != "" {
					parts = append(parts, l)
				}
			}
		}
	}
	return strings.Join(parts, "\n")
}

func parseTuning(path string) (*tNode, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var doc yaml.Node
	if err := yaml.Unmarshal(b, &doc); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	if len(doc.Content) != 1 || doc.Content[0].Kind != yaml.MappingNode {
		return nil, fmt.Errorf("%s: expected a mapping", path)
	}
	root := &tNode{key: "", kind: kMap, class: "Tuning"}
	if err := walkMap(doc.Content[0], root, "Tuning"); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return root, nil
}

func walkMap(m *yaml.Node, into *tNode, class string) error {
	for i := 0; i+1 < len(m.Content); i += 2 {
		k, v := m.Content[i], m.Content[i+1]
		n := &tNode{key: k.Value, doc: comment(k, v)}
		switch v.Kind {
		case yaml.MappingNode:
			n.kind = kMap
			n.class = class + Pascal(k.Value)
			if err := walkMap(v, n, n.class); err != nil {
				return err
			}
		case yaml.SequenceNode:
			if len(v.Content) == 0 {
				return fmt.Errorf("%s: empty list has no type", k.Value)
			}
			switch v.Content[0].Tag {
			case "!!int":
				n.kind = kIntList
			case "!!float":
				n.kind = kFloatList
			case "!!str":
				n.kind = kStringList
			default:
				return fmt.Errorf("%s: unsupported list item %s", k.Value, v.Content[0].Tag)
			}
			for _, it := range v.Content {
				if it.Tag != v.Content[0].Tag {
					return fmt.Errorf("%s: mixed list item types (write 12.0, not 12, in a float list)", k.Value)
				}
			}
		case yaml.ScalarNode:
			switch v.Tag {
			case "!!int":
				n.kind = kInt
			case "!!float":
				n.kind = kFloat
			case "!!bool":
				n.kind = kBool
			case "!!str":
				n.kind = kString
			default:
				return fmt.Errorf("%s: unsupported value %s", k.Value, v.Tag)
			}
		default:
			return fmt.Errorf("%s: unsupported node", k.Value)
		}
		into.children = append(into.children, n)
	}
	return nil
}

func classes(n *tNode, out *[]*tNode) {
	if n.kind != kMap {
		return
	}
	*out = append(*out, n)
	for _, c := range n.children {
		classes(c, out)
	}
}

// Tuning generates packages/shared_gen/lib/src/tuning.g.dart and web/src/gen/tuning.ts.
func Tuning(o *Output, src string) error {
	root, err := parseTuning(filepath.Join(o.Root, src))
	if err != nil {
		return err
	}
	root.doc = "Game numbers from content/tuning.yaml (METROPOLE_PLAN 5.1).\nParsing is strict: a missing or mistyped key is an error. The debug panel mutates fields\nand calls changed()."
	var cls []*tNode
	classes(root, &cls)
	o.Add("packages/shared_gen/lib/src/tuning.g.dart", []byte(tuningDart(cls, src)))
	o.Add("web/src/gen/tuning.ts", []byte(tuningTS(cls, src)))
	return nil
}

func dartType(n *tNode) string {
	switch n.kind {
	case kMap:
		return n.class
	case kInt:
		return "int"
	case kFloat:
		return "double"
	case kBool:
		return "bool"
	case kString:
		return "String"
	case kIntList:
		return "List<int>"
	case kFloatList:
		return "List<double>"
	default:
		return "List<String>"
	}
}

func dartRead(n *tNode) string {
	k := fmt.Sprintf("'%s'", n.key)
	switch n.kind {
	case kMap:
		return fmt.Sprintf("%s._(r.sub(%s))", n.class, k)
	case kInt:
		return "r.i(" + k + ")"
	case kFloat:
		return "r.d(" + k + ")"
	case kBool:
		return "r.b(" + k + ")"
	case kString:
		return "r.s(" + k + ")"
	case kIntList:
		return "r.il(" + k + ")"
	case kFloatList:
		return "r.dl(" + k + ")"
	default:
		return "r.sl(" + k + ")"
	}
}

const dartReader = `class _R {
  _R(this.map, this.path);
  final Map<Object?, Object?> map;
  final String path;

  Object _get(String key) {
    final v = map[key];
    if (v == null) throw FormatException('tuning: missing $path$key');
    return v;
  }

  Never _bad(String key, String what) => throw FormatException('tuning: $path$key must be $what');

  double d(String key) {
    final v = _get(key);
    return v is num ? v.toDouble() : _bad(key, 'a number');
  }

  int i(String key) {
    final v = _get(key);
    return v is int ? v : _bad(key, 'an integer');
  }

  bool b(String key) {
    final v = _get(key);
    return v is bool ? v : _bad(key, 'a boolean');
  }

  String s(String key) {
    final v = _get(key);
    return v is String ? v : _bad(key, 'a string');
  }

  List<Object?> _list(String key) {
    final v = _get(key);
    return v is List ? v : _bad(key, 'a list');
  }

  List<double> dl(String key) =>
      [for (final x in _list(key)) x is num ? x.toDouble() : _bad(key, 'a list of numbers')];
  List<int> il(String key) => [for (final x in _list(key)) x is int ? x : _bad(key, 'a list of integers')];
  List<String> sl(String key) => [for (final x in _list(key)) x is String ? x : _bad(key, 'a list of strings')];

  _R sub(String key) {
    final v = _get(key);
    return v is Map ? _R(v, '$path$key.') : _bad(key, 'a map');
  }
}

void _flatten(String prefix, Map<String, Object> m, Map<String, Object> out) {
  m.forEach((k, v) {
    final p = prefix.isEmpty ? k : '$prefix.$k';
    if (v is Map<String, Object>) {
      _flatten(p, v, out);
    } else {
      out[p] = v;
    }
  });
}
`

func tuningDart(cls []*tNode, src string) string {
	var b strings.Builder
	b.WriteString(Header("//", src))
	b.WriteString("// ignore_for_file: prefer_initializing_formals, unnecessary_this\n\n")
	b.WriteString("import 'package:yaml/yaml.dart';\n\n")
	b.WriteString(dartReader)
	for _, c := range cls {
		isRoot := c.class == "Tuning"
		b.WriteString("\n")
		b.WriteString(Doc("", c.doc))
		fmt.Fprintf(&b, "class %s {\n", c.class)
		fmt.Fprintf(&b, "  %s._(_R r)", c.class)
		for i, f := range c.children {
			sep := ","
			if i == 0 {
				sep = "\n      :"
			} else {
				sep = ",\n       "
			}
			fmt.Fprintf(&b, "%s %s = %s", sep, Field(f.key), dartRead(f))
		}
		b.WriteString(";\n")
		if isRoot {
			b.WriteString(`
  factory Tuning.fromYaml(String src) {
    final y = loadYaml(src);
    if (y is! Map) throw const FormatException('tuning: expected a map');
    return Tuning._(_R(y, ''));
  }

  factory Tuning.fromJson(Map<String, Object?> json) => Tuning._(_R(json, ''));
`)
		}
		for _, f := range c.children {
			b.WriteString("\n")
			b.WriteString(Doc("  ", f.doc))
			mod := ""
			if f.kind == kMap {
				mod = "final "
			}
			fmt.Fprintf(&b, "  %s%s %s;\n", mod, dartType(f), Field(f.key))
		}
		b.WriteString("\n  Map<String, Object> toJson() => {\n")
		for _, f := range c.children {
			v := Field(f.key)
			if f.kind == kMap {
				v += ".toJson()"
			}
			fmt.Fprintf(&b, "        '%s': %s,\n", f.key, v)
		}
		b.WriteString("      };\n")
		if k := c.numericMap(); k >= 0 {
			t := "double"
			if k == kInt {
				t = "int"
			}
			fmt.Fprintf(&b, "\n  /// Value by YAML key, null when the key is unknown.\n  %s? operator [](String key) => switch (key) {\n", t)
			for _, f := range c.children {
				fmt.Fprintf(&b, "        '%s' => %s,\n", f.key, Field(f.key))
			}
			b.WriteString("        _ => null,\n      };\n")
			fmt.Fprintf(&b, "\n  static const keys = [%s];\n", quoteList(c.children))
		}
		if isRoot {
			b.WriteString(`
  /// Dotted YAML path → value, for diffs against the loaded file.
  Map<String, Object> flatten() {
    final out = <String, Object>{};
    _flatten('', toJson(), out);
    return out;
  }

  final _listeners = <void Function()>[];
  void addListener(void Function() l) => _listeners.add(l);
  void removeListener(void Function() l) => _listeners.remove(l);

  /// Call after mutating fields (debug panel).
  void changed() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }
`)
		}
		b.WriteString("}\n")
	}
	return b.String()
}

func quoteList(ns []*tNode) string {
	q := make([]string, len(ns))
	for i, n := range ns {
		q[i] = "'" + n.key + "'"
	}
	return strings.Join(q, ", ")
}

func tsType(n *tNode) string {
	switch n.kind {
	case kMap:
		return n.class
	case kInt, kFloat:
		return "number"
	case kBool:
		return "boolean"
	case kString:
		return "string"
	case kIntList, kFloatList:
		return "number[]"
	default:
		return "string[]"
	}
}

func tsRead(n *tNode) string {
	k := fmt.Sprintf("'%s'", n.key)
	switch n.kind {
	case kMap:
		return fmt.Sprintf("new %s(r.sub(%s))", n.class, k)
	case kInt:
		return "r.i(" + k + ")"
	case kFloat:
		return "r.d(" + k + ")"
	case kBool:
		return "r.b(" + k + ")"
	case kString:
		return "r.s(" + k + ")"
	case kIntList:
		return "r.il(" + k + ")"
	case kFloatList:
		return "r.dl(" + k + ")"
	default:
		return "r.sl(" + k + ")"
	}
}

const tsReader = `class R {
  constructor(
    private readonly map: Record<string, unknown>,
    private readonly path: string,
  ) {}

  private get(key: string): unknown {
    const v = this.map[key];
    if (v === undefined || v === null) throw new Error(` + "`tuning: missing ${this.path}${key}`" + `);
    return v;
  }

  private bad(key: string, what: string): never {
    throw new Error(` + "`tuning: ${this.path}${key} must be ${what}`" + `);
  }

  d(key: string): number {
    const v = this.get(key);
    return typeof v === 'number' ? v : this.bad(key, 'a number');
  }

  i(key: string): number {
    const v = this.get(key);
    return typeof v === 'number' && Number.isInteger(v) ? v : this.bad(key, 'an integer');
  }

  b(key: string): boolean {
    const v = this.get(key);
    return typeof v === 'boolean' ? v : this.bad(key, 'a boolean');
  }

  s(key: string): string {
    const v = this.get(key);
    return typeof v === 'string' ? v : this.bad(key, 'a string');
  }

  private list(key: string): unknown[] {
    const v = this.get(key);
    return Array.isArray(v) ? v : this.bad(key, 'a list');
  }

  dl(key: string): number[] {
    return this.list(key).map((x) => (typeof x === 'number' ? x : this.bad(key, 'a list of numbers')));
  }

  il(key: string): number[] {
    return this.list(key).map((x) =>
      typeof x === 'number' && Number.isInteger(x) ? x : this.bad(key, 'a list of integers'),
    );
  }

  sl(key: string): string[] {
    return this.list(key).map((x) => (typeof x === 'string' ? x : this.bad(key, 'a list of strings')));
  }

  sub(key: string): R {
    const v = this.get(key);
    if (typeof v !== 'object' || Array.isArray(v)) this.bad(key, 'a map');
    return new R(v as Record<string, unknown>, ` + "`${this.path}${key}.`" + `);
  }
}
`

func tuningTS(cls []*tNode, src string) string {
	var b strings.Builder
	b.WriteString(Header("//", src))
	b.WriteString("/* eslint-disable */\n\n")
	b.WriteString(tsReader)
	for _, c := range cls {
		isRoot := c.class == "Tuning"
		b.WriteString("\n")
		b.WriteString(TSDoc("", c.doc))
		fmt.Fprintf(&b, "export class %s {\n", c.class)
		for _, f := range c.children {
			b.WriteString(TSDoc("  ", f.doc))
			ro := ""
			if f.kind == kMap {
				ro = "readonly "
			}
			fmt.Fprintf(&b, "  %s%s: %s;\n", ro, Field(f.key), tsType(f))
		}
		vis := ""
		if isRoot {
			vis = "private "
		}
		fmt.Fprintf(&b, "\n  %sconstructor(r: R) {\n", vis)
		for _, f := range c.children {
			fmt.Fprintf(&b, "    this.%s = %s;\n", Field(f.key), tsRead(f))
		}
		b.WriteString("  }\n")
		b.WriteString("\n  toJson(): Record<string, unknown> {\n    return {\n")
		for _, f := range c.children {
			v := "this." + Field(f.key)
			if f.kind == kMap {
				v += ".toJson()"
			}
			fmt.Fprintf(&b, "      %s: %s,\n", f.key, v)
		}
		b.WriteString("    };\n  }\n")
		if k := c.numericMap(); k >= 0 {
			b.WriteString("\n  /** Value by YAML key, undefined when the key is unknown. */\n  get(key: string): number | undefined {\n    switch (key) {\n")
			for _, f := range c.children {
				fmt.Fprintf(&b, "      case '%s':\n        return this.%s;\n", f.key, Field(f.key))
			}
			b.WriteString("      default:\n        return undefined;\n    }\n  }\n")
			fmt.Fprintf(&b, "\n  static readonly keys = [%s] as const;\n", quoteList(c.children))
		}
		if isRoot {
			b.WriteString(`
  /** Parses the JSON form of tuning.yaml (metro sync writes tuning.json for the web). */
  static fromJson(json: unknown): Tuning {
    if (typeof json !== 'object' || json === null || Array.isArray(json)) throw new Error('tuning: expected a map');
    return new Tuning(new R(json as Record<string, unknown>, ''));
  }

  private readonly listeners: Array<() => void> = [];
  addListener(l: () => void): void {
    this.listeners.push(l);
  }
  /** Call after mutating fields (debug panel). */
  changed(): void {
    for (const l of [...this.listeners]) l();
  }
`)
		}
		b.WriteString("}\n")
	}
	return b.String()
}
