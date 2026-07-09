package dind

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestEnvEnabled(t *testing.T) {
	t.Setenv("PROVEO_DIND", "")
	if EnvEnabled() {
		t.Fatal("expected false with empty env")
	}
	t.Setenv("PROVEO_DIND", "1")
	if !EnvEnabled() {
		t.Fatal("PROVEO_DIND=1 should enable")
	}
	t.Setenv("PROVEO_DIND", "true")
	if !EnvEnabled() {
		t.Fatal("PROVEO_DIND=true should enable")
	}
	t.Setenv("PROVEO_DIND", "0")
	if EnvEnabled() {
		t.Fatal("PROVEO_DIND=0 should not enable")
	}
}

func TestScopeHasDockerfiles(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	if ScopeHasDockerfiles(root) {
		t.Fatal("empty dir should not match")
	}
	if err := os.WriteFile(filepath.Join(root, "Dockerfile"), []byte("FROM scratch\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if !ScopeHasDockerfiles(root) {
		t.Fatal("Dockerfile at root should match")
	}

	nested := t.TempDir()
	deep := nested
	for i := 0; i < 3; i++ {
		deep = filepath.Join(deep, "d")
		if err := os.MkdirAll(deep, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(deep, "compose.yml"), []byte("services: {}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if !ScopeHasDockerfiles(nested) {
		t.Fatal("compose.yml within maxdepth should match")
	}

	// Prune via .gitignore directory basename
	pruned := t.TempDir()
	if err := os.WriteFile(filepath.Join(pruned, ".gitignore"), []byte("vendor/\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(pruned, "vendor"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(pruned, "vendor", "Dockerfile"), []byte("FROM scratch\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if ScopeHasDockerfiles(pruned) {
		t.Fatal("Dockerfile under gitignored dir basename should be pruned")
	}
}

func TestShouldStart(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "Dockerfile"), []byte("FROM scratch\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PROVEO_DIND", "")

	if ShouldStart(false, root, true, func() bool { return true }) {
		t.Fatal("non-capable must never start")
	}
	if ShouldStart(true, root, false, nil) {
		t.Fatal("non-interactive without env must not start")
	}
	if !ShouldStart(true, root, true, func() bool { return true }) {
		t.Fatal("interactive yes should start")
	}
	if ShouldStart(true, root, true, func() bool { return false }) {
		t.Fatal("interactive no should not start")
	}
	t.Setenv("PROVEO_DIND", "1")
	if !ShouldStart(true, root, false, nil) {
		t.Fatal("PROVEO_DIND=1 should start without prompt")
	}
}

func TestPromptYesNo(t *testing.T) {
	t.Parallel()
	var out strings.Builder
	if !PromptYesNo(strings.NewReader("y\n"), &out) {
		t.Fatal("y should be yes")
	}
	if PromptYesNo(strings.NewReader("n\n"), &out) {
		t.Fatal("n should be no")
	}
	if PromptYesNo(strings.NewReader("\n"), &out) {
		t.Fatal("empty should be no")
	}
}

type fakeRunner struct {
	calls [][]string
}

func (f *fakeRunner) Run(args ...string) error {
	f.calls = append(f.calls, append([]string(nil), args...))
	return nil
}

func TestStartAndAgentArgs(t *testing.T) {
	t.Parallel()
	r := &fakeRunner{}
	var warn strings.Builder
	s, err := Start(r, "opencode", "/tmp/scope", &warn)
	if err != nil {
		t.Fatal(err)
	}
	if s.Name != "proveo-dind-opencode" {
		t.Fatalf("name = %q", s.Name)
	}
	args := s.AgentArgs()
	joined := strings.Join(args, " ")
	if !strings.Contains(joined, "--link") || !strings.Contains(joined, "DOCKER_HOST=tcp://docker:2375") {
		t.Fatalf("agent args missing link/host: %v", args)
	}
	// last call should be docker run ... docker:dind
	last := r.calls[len(r.calls)-1]
	if last[0] != "run" || last[len(last)-1] != "docker:dind" {
		t.Fatalf("unexpected start call: %v", last)
	}
	if !strings.Contains(warn.String(), "Security warning") {
		t.Fatal("expected security warning on stderr")
	}
	s.Cleanup(r)
	if s.Name != "" {
		t.Fatal("cleanup should clear name")
	}
}
