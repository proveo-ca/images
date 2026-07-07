package workspace

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/proveo-ca/proveo/internal/manifest"
	"github.com/proveo-ca/proveo/internal/runner"
)

// rootFiles are workspace-shared files preserved (read-only) from the repo root
// into a monorepo-subdir `/app` mount. A superset across harnesses; each is
// mounted only if it exists at the root and not already in the scope dir — so
// the union is safe (a harness never sees a file its repo doesn't have).
var rootFiles = []string{
	"AGENTS.md", "CONVENTIONS.md", "CLAUDE.md", ".cursorrules",
	"package.json", "pnpm-workspace.yaml", "pnpm-lock.yaml", "package-lock.json",
	"yarn.lock", "turbo.json", "nx.json", "opencode.json", "opencode.jsonc",
}

// MountSpec is the resolved input to mount planning: the manifest's mount model
// (embedded — the single source of that shape, D5) plus the concrete paths for
// this run. It lives beside the git-scope resolver here, not in runner, which
// stays a pure argv formatter (D4).
type MountSpec struct {
	manifest.Workspace        // Layout, ConfigDir, GitMode, Output, Mode
	RepoRoot           string // git root; "" when not in a repo
	InputDir           string // invocation dir (absolute) — the monorepo scope when a subdir
	OutputDir          string
}

// Plan returns the bind mounts and container workdir for the spec, reproducing
// the per-harness run.sh mount models. It inspects the filesystem (existence of
// root files / config dir / .env) exactly as the Bash did.
func (w MountSpec) Plan() (mounts []runner.Mount, workdir string) {
	if w.Layout == "input-output" {
		return []runner.Mount{
			{Host: w.InputDir, Container: "/workspace/input", ReadOnly: true},
			{Host: w.OutputDir, Container: "/workspace/output"},
		}, ""
	}

	ro := w.Mode == "ro"
	gitRO := w.GitMode == "ro"
	switch {
	case w.RepoRoot != "" && sameDir(w.InputDir, w.RepoRoot):
		mounts = append(mounts, runner.Mount{Host: w.RepoRoot, Container: "/app", ReadOnly: ro})
	case w.RepoRoot != "" && underDir(w.InputDir, w.RepoRoot):
		rel := relSlash(w.RepoRoot, w.InputDir)
		mounts = append(mounts,
			runner.Mount{Host: w.InputDir, Container: "/app/" + rel, ReadOnly: ro},
			runner.Mount{Host: filepath.Join(w.RepoRoot, ".git"), Container: "/app/.git", ReadOnly: gitRO},
		)
		for _, f := range rootFiles {
			if exists(filepath.Join(w.RepoRoot, f)) && !exists(filepath.Join(w.InputDir, f)) {
				mounts = append(mounts, runner.Mount{Host: filepath.Join(w.RepoRoot, f), Container: "/app/" + f, ReadOnly: true})
			}
		}
		if w.ConfigDir != "" && exists(filepath.Join(w.RepoRoot, w.ConfigDir)) && !exists(filepath.Join(w.InputDir, w.ConfigDir)) {
			mounts = append(mounts, runner.Mount{Host: filepath.Join(w.RepoRoot, w.ConfigDir), Container: "/app/" + w.ConfigDir, ReadOnly: true})
		}
		if env := firstExisting(filepath.Join(w.InputDir, ".env"), filepath.Join(w.RepoRoot, ".env")); env != "" {
			mounts = append(mounts, runner.Mount{Host: env, Container: "/app/.env", ReadOnly: true})
		}
	default: // not a repo
		mounts = append(mounts, runner.Mount{Host: w.InputDir, Container: "/app", ReadOnly: ro})
	}
	if w.Output && w.OutputDir != "" {
		mounts = append(mounts, runner.Mount{Host: w.OutputDir, Container: "/app/output"})
	}
	return mounts, "/app"
}

func sameDir(a, b string) bool { return filepath.Clean(a) == filepath.Clean(b) }

func underDir(path, root string) bool {
	root = filepath.Clean(root) + string(filepath.Separator)
	return strings.HasPrefix(filepath.Clean(path)+string(filepath.Separator), root)
}

func relSlash(root, path string) string {
	rel, err := filepath.Rel(root, path)
	if err != nil {
		return filepath.Base(path)
	}
	return filepath.ToSlash(rel)
}

func exists(p string) bool { _, err := os.Stat(p); return err == nil }

func firstExisting(paths ...string) string {
	for _, p := range paths {
		if exists(p) {
			return p
		}
	}
	return ""
}
