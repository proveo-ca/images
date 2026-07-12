package verify

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/google/go-cmp/cmp"
)

func TestDetectGoMod(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "go.mod"), []byte("module x\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	got := Detect(root, func(string) (string, error) { return "", os.ErrNotExist })
	want := []Command{
		{Category: "test", Cmd: "go test ./..."},
		{Category: "build", Cmd: "go build ./..."},
	}
	if diff := cmp.Diff(want, got); diff != "" {
		t.Errorf("Detect(go.mod) mismatch (-want +got):\n%s", diff)
	}
}

func TestDetectPnpmPackageJSON(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "package.json"), []byte(`{"scripts":{"test":"vitest","lint":"eslint .","build":"vite build"}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "pnpm-lock.yaml"), []byte("lockfileVersion: '9'\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	got := Detect(root, func(string) (string, error) { return "", os.ErrNotExist })
	want := []Command{
		{Category: "test", Cmd: "pnpm test"},
		{Category: "lint", Cmd: "pnpm lint"},
		{Category: "build", Cmd: "pnpm build"},
	}
	if diff := cmp.Diff(want, got); diff != "" {
		t.Errorf("Detect(pnpm) mismatch (-want +got):\n%s", diff)
	}
}

func TestDetectRustAndDocker(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "Cargo.toml"), []byte("[package]\nname='x'\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "Dockerfile"), []byte("FROM scratch\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	got := Detect(root, func(string) (string, error) { return "", os.ErrNotExist })
	want := []Command{
		{Category: "test", Cmd: "cargo test"},
		{Category: "build", Cmd: "cargo build"},
		{Category: "lint", Cmd: "cargo clippy"},
		{Category: "build", Cmd: "docker build ."},
	}
	if diff := cmp.Diff(want, got); diff != "" {
		t.Errorf("Detect(rust+docker) mismatch (-want +got):\n%s", diff)
	}
}

func TestFormatLines(t *testing.T) {
	t.Parallel()
	got := FormatLines([]Command{{Category: "test", Cmd: "go test ./..."}})
	if got != "test|go test ./..." {
		t.Errorf("FormatLines = %q", got)
	}
}
