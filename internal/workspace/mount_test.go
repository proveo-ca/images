package workspace

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/google/go-cmp/cmp"

	"github.com/proveo-ca/proveo/internal/manifest"
	"github.com/proveo-ca/proveo/internal/runner"
)

func touch(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestMountPlanInputOutput(t *testing.T) {
	t.Parallel()
	got, wd := MountSpec{Workspace: manifest.Workspace{Layout: "input-output"}, InputDir: "/repo", OutputDir: "/repo/reports"}.Plan()
	want := []runner.Mount{
		{Host: "/repo", Container: "/workspace/input", ReadOnly: true},
		{Host: "/repo/reports", Container: "/workspace/output"},
	}
	if diff := cmp.Diff(want, got); diff != "" {
		t.Errorf("input-output mounts mismatch (-want +got):\n%s", diff)
	}
	if wd != "" {
		t.Errorf("input-output workdir = %q, want empty", wd)
	}
}

func TestMountPlanAppWholeRepo(t *testing.T) {
	t.Parallel()
	got, wd := MountSpec{Workspace: manifest.Workspace{Layout: "app"}, RepoRoot: "/repo", InputDir: "/repo"}.Plan()
	want := []runner.Mount{{Host: "/repo", Container: "/app"}}
	if diff := cmp.Diff(want, got); diff != "" {
		t.Errorf("app whole-repo mounts mismatch (-want +got):\n%s", diff)
	}
	if wd != "/app" {
		t.Errorf("workdir = %q, want /app", wd)
	}
}

func TestMountPlanAppSubdir(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	touch(t, filepath.Join(root, "package.json"))
	touch(t, filepath.Join(root, "pnpm-workspace.yaml"))
	touch(t, filepath.Join(root, ".cursor", "cli.json"))
	touch(t, filepath.Join(root, ".env"))
	scope := filepath.Join(root, "apps", "web")
	touch(t, filepath.Join(scope, "package.json")) // scope has its own package.json

	got, wd := MountSpec{
		Workspace: manifest.Workspace{Layout: "app", ConfigDir: ".cursor", GitMode: "rw"},
		RepoRoot:  root, InputDir: scope,
	}.Plan()

	if wd != "/app" {
		t.Fatalf("workdir = %q, want /app", wd)
	}
	// Index the produced mounts by container path for order-independent assertions.
	byContainer := map[string]runner.Mount{}
	for _, m := range got {
		byContainer[m.Container] = m
	}
	// scope mounted at /app/apps/web (rw)
	if m, ok := byContainer["/app/apps/web"]; !ok || m.Host != scope || m.ReadOnly {
		t.Errorf("scope mount = %+v (ok=%v), want host=%s rw at /app/apps/web", m, ok, scope)
	}
	// root .git mounted rw
	if m, ok := byContainer["/app/.git"]; !ok || m.ReadOnly {
		t.Errorf(".git mount = %+v (ok=%v), want rw", m, ok)
	}
	// root pnpm-workspace.yaml preserved ro (scope lacks it)
	if m, ok := byContainer["/app/pnpm-workspace.yaml"]; !ok || !m.ReadOnly {
		t.Errorf("pnpm-workspace.yaml not preserved ro: %+v (ok=%v)", m, ok)
	}
	// scope HAS its own package.json → root package.json NOT preserved
	if m, ok := byContainer["/app/package.json"]; ok {
		t.Errorf("root package.json should not be mounted (scope has its own): %+v", m)
	}
	// .cursor config dir preserved ro; .env preserved ro
	if _, ok := byContainer["/app/.cursor"]; !ok {
		t.Error(".cursor config dir not preserved")
	}
	if m, ok := byContainer["/app/.env"]; !ok || !m.ReadOnly {
		t.Errorf(".env not preserved ro: %+v (ok=%v)", m, ok)
	}
}

func TestMountPlanAppGitROAndOutput(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	scope := filepath.Join(root, "svc")
	touch(t, filepath.Join(scope, "go.mod"))
	got, _ := MountSpec{
		Workspace: manifest.Workspace{Layout: "app", GitMode: "ro", Output: true},
		RepoRoot:  root, InputDir: scope, OutputDir: "/out",
	}.Plan()
	byContainer := map[string]runner.Mount{}
	for _, m := range got {
		byContainer[m.Container] = m
	}
	if m, ok := byContainer["/app/.git"]; !ok || !m.ReadOnly {
		t.Errorf("gitMode=ro should mount .git read-only: %+v (ok=%v)", m, ok)
	}
	if m, ok := byContainer["/app/output"]; !ok || m.Host != "/out" || m.ReadOnly {
		t.Errorf("output mount = %+v (ok=%v), want /out rw at /app/output", m, ok)
	}
}

func TestMountPlanAppNonRepoReadOnly(t *testing.T) {
	t.Parallel()
	// Mode:"ro" (now wired via manifest.Workspace, D6) makes the /app mount read-only.
	got, wd := MountSpec{Workspace: manifest.Workspace{Layout: "app", Mode: "ro"}, InputDir: "/somedir"}.Plan()
	want := []runner.Mount{{Host: "/somedir", Container: "/app", ReadOnly: true}}
	if diff := cmp.Diff(want, got); diff != "" {
		t.Errorf("app non-repo ro mounts mismatch (-want +got):\n%s", diff)
	}
	if wd != "/app" {
		t.Errorf("workdir = %q, want /app", wd)
	}
}
