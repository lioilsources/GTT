package npc

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func write(t *testing.T, root, rel, body string) {
	t.Helper()
	p := filepath.Join(root, rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestCheckAndLoad(t *testing.T) {
	root := t.TempDir()
	write(t, root, "design/tokens.json", `{"color": {"npc": {"portraits": ["#000000"]}}}`)
	write(t, root, "content/npc/characters.yaml", "characters:\n  - {id: a, portrait: 0}\n  - {id: b, portrait: 3}\n")
	write(t, root, "content/npc/skits/b_2.yaml", "id: b_2\ncharacter: a\n")
	write(t, root, "content/npc/skits/a_1.yaml", "id: a_1\ncharacter: a\n")
	write(t, root, "content/npc/skits/x.yaml", "id: y\ncharacter: zz\n")

	errs := Check(root)
	var msgs []string
	for _, e := range errs {
		msgs = append(msgs, e.Error())
	}
	all := strings.Join(msgs, "\n")
	for _, want := range []string{"b portrait 3", `id "y" must match`, `unknown character "zz"`} {
		if !strings.Contains(all, want) {
			t.Errorf("missing %q in:\n%s", want, all)
		}
	}
	if len(errs) != 3 {
		t.Errorf("got %d errors, want 3:\n%s", len(errs), all)
	}

	p, err := Load(root)
	if err != nil {
		t.Fatal(err)
	}
	var ids []string
	for _, s := range p.Skits {
		ids = append(ids, s["id"].(string))
	}
	if strings.Join(ids, ",") != "a_1,b_2,y" {
		t.Errorf("skits not sorted by id: %v", ids)
	}
}
