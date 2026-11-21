// Package guard enforces path ownership per session branch (DUALSTACK 3).
package guard

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"

	"metro/internal/repo"
)

type Config struct {
	Owners struct {
		Flutter         []string `yaml:"flutter"`
		Web             []string `yaml:"web"`
		SharedGenerated []string `yaml:"shared_generated"`
	} `yaml:"owners"`
	BootstrapBranches []string `yaml:"bootstrap_branches"`
}

func Load(root string) (*Config, error) {
	b, err := os.ReadFile(filepath.Join(root, repo.GuardConfig))
	if err != nil {
		return nil, err
	}
	var c Config
	return &c, yaml.Unmarshal(b, &c)
}

func hasPrefix(p string, dirs []string) bool {
	for _, d := range dirs {
		if strings.HasPrefix(p, d) {
			return true
		}
	}
	return false
}

// Owner returns "flutter", "web" or "shared" for a repo-relative path.
func (c *Config) Owner(path string) string {
	switch {
	case hasPrefix(path, c.Owners.SharedGenerated):
		return "shared"
	case hasPrefix(path, c.Owners.Flutter):
		return "flutter"
	case hasPrefix(path, c.Owners.Web):
		return "web"
	}
	return "shared"
}

// Session derives the session from a branch name; "" means the branch is not guarded.
func Session(branch string) (string, error) {
	for _, s := range []string{"flutter", "web", "shared"} {
		if strings.HasPrefix(branch, s+"/") {
			return s, nil
		}
	}
	if branch == "main" || branch == "" {
		return "", nil
	}
	return "", fmt.Errorf("branch %q has no session prefix (flutter/, web/, shared/)", branch)
}

// Violations lists changed paths the branch may not touch.
func (c *Config) Violations(branch string, changed []string) ([]string, error) {
	for _, b := range c.BootstrapBranches {
		if b == branch {
			return nil, nil
		}
	}
	s, err := Session(branch)
	if err != nil || s == "" {
		return nil, err
	}
	var bad []string
	for _, p := range changed {
		if o := c.Owner(p); o != s {
			bad = append(bad, fmt.Sprintf("%s (owned by %s)", p, o))
		}
	}
	return bad, nil
}

// CurrentBranch prefers the CI variables, then git.
func CurrentBranch(root string) (string, error) {
	for _, v := range []string{"GITHUB_HEAD_REF", "GITHUB_REF_NAME"} {
		if b := os.Getenv(v); b != "" {
			return b, nil
		}
	}
	out, err := git(root, "rev-parse", "--abbrev-ref", "HEAD")
	return strings.TrimSpace(out), err
}

// Changed lists files changed on this branch since it left base.
func Changed(root, base string) ([]string, error) {
	out, err := git(root, "diff", "--name-only", base+"...HEAD")
	if err != nil {
		return nil, err
	}
	var files []string
	for _, l := range strings.Split(strings.TrimSpace(out), "\n") {
		if l != "" {
			files = append(files, l)
		}
	}
	return files, nil
}

func git(root string, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = root
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("git %s: %w\n%s", strings.Join(args, " "), err, out)
	}
	return string(out), nil
}
