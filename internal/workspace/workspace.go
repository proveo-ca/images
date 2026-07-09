// Package workspace resolves the monorepo scope for a run: the git repo root
// and the repo-relative prefix of the start directory, so a harness launched
// from a subproject still mounts full repo/git context (, porting
// the monorepo logic from apps/cli/public/cli/lib/workspace.sh).
package workspace

import (
	"os/exec"
	"strings"
)

// Scope is the resolved monorepo position of a start directory.
type Scope struct {
	Root   string // git toplevel, or the start dir when not in a repo
	Prefix string // repo-relative path of the start dir ("" at root / no repo)
	IsRepo bool
}

// gitFunc runs `git -C dir args...` and returns trimmed stdout; injectable for tests.
type gitFunc func(dir string, args ...string) (string, error)

func realGit(dir string, args ...string) (string, error) {
	out, err := exec.Command("git", append([]string{"-C", dir}, args...)...).Output()
	return strings.TrimSpace(string(out)), err
}

// Resolve determines the scope of dir using the real git binary.
func Resolve(dir string) Scope { return resolveWith(dir, realGit) }

func resolveWith(dir string, git gitFunc) Scope {
	root, err := git(dir, "rev-parse", "--show-toplevel")
	if err != nil || root == "" {
		return Scope{Root: dir}
	}
	prefix, _ := git(dir, "rev-parse", "--show-prefix") // e.g. "apps/web/"
	return Scope{Root: root, Prefix: strings.TrimSuffix(prefix, "/"), IsRepo: true}
}
