package egress

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestStageSquidConfig(t *testing.T) {
	t.Parallel()
	// Read the real def files from the repo tree (this test runs in internal/egress).
	repoRoot := filepath.Join("..", "..")
	dest := t.TempDir()

	if err := StageSquidConfig(os.DirFS(repoRoot), dest, []string{"anthropic"}, ""); err != nil {
		t.Fatalf("StageSquidConfig: %v", err)
	}

	for _, name := range append(squidStaticFiles, "provider-allow.conf") {
		if _, err := os.Stat(filepath.Join(dest, name)); err != nil {
			t.Errorf("staged config missing %s: %v", name, err)
		}
	}

	got, err := os.ReadFile(filepath.Join(dest, "provider-allow.conf"))
	if err != nil {
		t.Fatalf("read provider-allow.conf: %v", err)
	}
	for _, want := range []string{"acl provider_allow dstdomain .anthropic.com", "http_access allow unsafe_methods provider_allow"} {
		if !strings.Contains(string(got), want) {
			t.Errorf("provider-allow.conf missing %q; got:\n%s", want, got)
		}
	}
}

func TestStageSquidConfigMissingSource(t *testing.T) {
	t.Parallel()
	if err := StageSquidConfig(os.DirFS(t.TempDir()), t.TempDir(), nil, ""); err == nil {
		t.Fatal("StageSquidConfig with no source files = nil error, want error")
	}
}
