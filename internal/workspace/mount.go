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
	// EgressMode controls whether a project .env is bind-mounted into the agent.
	// broker (default/empty when unset): mount resolved .env at /app/.env:ro when present.
	// proxy|firewall: never mount secrets; mask .env paths with /dev/null.
	EgressMode string
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
		mounts = append(mounts, w.envMounts("")...)
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
		mounts = append(mounts, w.envMounts(rel)...)
	default: // not a repo
		mounts = append(mounts, runner.Mount{Host: w.InputDir, Container: "/app", ReadOnly: ro})
		mounts = append(mounts, w.envMounts("")...)
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

func (w MountSpec) isolateEnv() bool {
	switch strings.ToLower(strings.TrimSpace(w.EgressMode)) {
	case "proxy", "firewall":
		return true
	}
	return false
}

// envMounts returns .env-related mounts. In broker mode, overlay the resolved
// host file at /app/.env. In proxy/firewall, mask any .env that a bind would
// expose so secrets stay on the host / broker sidecar.
func (w MountSpec) envMounts(relativeScope string) []runner.Mount {
	if w.isolateEnv() {
		var out []runner.Mount
		if relativeScope != "" {
			if exists(filepath.Join(w.InputDir, ".env")) {
				out = append(out, runner.Mount{Host: "/dev/null", Container: "/app/" + relativeScope + "/.env", ReadOnly: true})
			}
			if w.RepoRoot != "" && exists(filepath.Join(w.RepoRoot, ".env")) {
				out = append(out, runner.Mount{Host: "/dev/null", Container: "/app/.env", ReadOnly: true})
			}
			return out
		}
		if exists(filepath.Join(w.InputDir, ".env")) || (w.RepoRoot != "" && exists(filepath.Join(w.RepoRoot, ".env"))) {
			out = append(out, runner.Mount{Host: "/dev/null", Container: "/app/.env", ReadOnly: true})
		}
		return out
	}
	if env := envMountSource(w.InputDir, w.RepoRoot); env != "" {
		return []runner.Mount{{Host: env, Container: "/app/.env", ReadOnly: true}}
	}
	return nil
}

func envMountSource(inputDir, repoRoot string) string {
	candidates := []string{filepath.Join(inputDir, ".env")}
	if repoRoot != "" {
		candidates = append(candidates, filepath.Join(repoRoot, ".env"))
	}
	for _, candidate := range candidates {
		if resolved := resolveRegularFile(candidate); resolved != "" {
			return resolved
		}
	}
	return ""
}

// resolveRegularFile returns the absolute path of a regular file, following
// symlinks on the host. Used for .env overlays when the project symlink points
// outside the bind-mounted tree.
func resolveRegularFile(path string) string {
	if _, err := os.Lstat(path); err != nil {
		return ""
	}
	resolved, err := filepath.EvalSymlinks(path)
	if err != nil {
		return ""
	}
	fi, err := os.Stat(resolved)
	if err != nil || !fi.Mode().IsRegular() {
		return ""
	}
	abs, err := filepath.Abs(resolved)
	if err != nil {
		return resolved
	}
	return abs
}

// EnvFileSource returns a host-side .env path for broker ingestion (never for
// agent mounts in proxy/firewall). Prefers inputDir, then repoRoot.
func EnvFileSource(inputDir, repoRoot string) string {
	return envMountSource(inputDir, repoRoot)
}
