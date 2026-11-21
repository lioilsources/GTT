// Package repo locates the monorepo root and its well-known paths.
package repo

import (
	"fmt"
	"os"
	"path/filepath"
)

// Root walks up from the working directory to the directory holding parity.yaml.
func Root() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "parity.yaml")); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("parity.yaml not found above the working directory; run metro inside the repo")
		}
		dir = parent
	}
}

// Well-known paths relative to the root.
const (
	Tuning      = "content/tuning.yaml"
	Cars        = "content/cars"
	Cities      = "content/cities"
	Catalog     = "content/minigames/catalog.yaml"
	I18n        = "i18n"
	Tokens      = "design/tokens.json"
	Schema      = "schema"
	Vectors     = "vectors"
	Scenarios   = "scenarios"
	Parity      = "parity.yaml"
	Assets      = "assets"
	Proto       = "tools/citypack/proto"
	DartGen     = "packages/shared_gen"
	TSGen       = "web/src/gen"
	AppShared   = "app/assets/shared"
	WebShared   = "web/public/shared"
	Packs       = "build/packs"
	PacksLock   = "packs.lock"
	GuardConfig = "metro.yaml"
)
