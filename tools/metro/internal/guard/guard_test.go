package guard

import "testing"

func cfg() *Config {
	c := &Config{BootstrapBranches: []string{"shared/d0"}}
	c.Owners.Flutter = []string{"app/", "packages/"}
	c.Owners.Web = []string{"web/"}
	c.Owners.SharedGenerated = []string{"packages/shared_gen/", "web/src/gen/"}
	return c
}

func TestOwnership(t *testing.T) {
	c := cfg()
	for path, want := range map[string]string{
		"app/lib/main.dart": "flutter", "packages/drive_core/lib/a.dart": "flutter",
		"packages/shared_gen/lib/src/tuning.g.dart": "shared", "web/src/main.ts": "web",
		"web/src/gen/tuning.ts": "shared", "content/tuning.yaml": "shared", "tools/metro/go.mod": "shared",
	} {
		if got := c.Owner(path); got != want {
			t.Errorf("Owner(%s) = %s, want %s", path, got, want)
		}
	}
}

func TestViolations(t *testing.T) {
	c := cfg()
	bad, err := c.Violations("web/F-001-sirky", []string{"web/src/a.ts", "content/tuning.yaml", "web/src/gen/x.ts"})
	if err != nil || len(bad) != 2 {
		t.Fatalf("got %v %v", bad, err)
	}
	if bad, _ := c.Violations("shared/d0", []string{"app/x"}); len(bad) != 0 {
		t.Fatal("bootstrap branch must pass")
	}
	if _, err := c.Violations("feature/x", nil); err == nil {
		t.Fatal("unknown prefix must fail")
	}
	if bad, err := c.Violations("main", []string{"app/x"}); err != nil || bad != nil {
		t.Fatal("main is not guarded")
	}
}
