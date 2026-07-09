// SPEC: _spec/tests/20-contract.puml
//
// Package contract holds Layer 2 no-Docker contracts that used to live as
// grep-for-substring asserts in defs/tests/test_harness_contracts.sh. These
// tests execute (or load) the real Go sources of truth.
package contract_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	proveo "github.com/proveo-ca/proveo"
	"github.com/proveo-ca/proveo/internal/entrypoint"
	"github.com/proveo-ca/proveo/internal/manifest"
	"github.com/proveo-ca/proveo/internal/provider"
	"github.com/proveo-ca/proveo/internal/runner"
)

func repoRoot(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	return filepath.Join(wd, "..", "..")
}

func TestEmbeddedManifestsLoad(t *testing.T) {
	t.Parallel()
	ms, err := manifest.LoadFS(proveo.Manifests)
	if err != nil {
		t.Fatalf("LoadFS(Manifests): %v", err)
	}
	targets, err := manifest.Targets(ms)
	if err != nil {
		t.Fatalf("Targets: %v", err)
	}
	for _, name := range []string{"cursor", "opencode", "cecli", "claudecode"} {
		img, ok := targets[name]
		if !ok {
			t.Errorf("missing target %q in embedded manifests", name)
			continue
		}
		if !strings.HasPrefix(img, "proveo/") {
			t.Errorf("target %q image = %q, want proveo/*", name, img)
		}
	}
}

func TestRunnerHardeningBaseline(t *testing.T) {
	t.Parallel()
	got := strings.Join(runner.Hardening(), " ")
	for _, want := range []string{"--cap-drop=ALL", "--security-opt=no-new-privileges:true", "--pids-limit=100"} {
		if !strings.Contains(got, want) {
			t.Errorf("Hardening() = %q, missing %q", got, want)
		}
	}
	argv := strings.Join(runner.DockerRunArgs(runner.Config{Image: "x"}), " ")
	if !strings.Contains(argv, "--cap-drop=ALL") {
		t.Errorf("DockerRunArgs must always include cap-drop: %s", argv)
	}
}

func TestRunShimsExecProveo(t *testing.T) {
	t.Parallel()
	root := repoRoot(t)
	for _, shim := range []string{"opencode", "cursor", "cecli", "claudecode"} {
		path := filepath.Join(root, "defs", shim, "run.sh")
		b, err := os.ReadFile(path)
		if err != nil {
			t.Errorf("read %s: %v", path, err)
			continue
		}
		body := string(b)
		if !strings.Contains(body, `exec "$PROVEO_BIN" run`) {
			t.Errorf("%s must exec proveo run", path)
		}
		if strings.Contains(body, "--cap-drop=ALL") {
			t.Errorf("%s must not redeclare hardening (lives in internal/runner)", path)
		}
	}
}

func TestEntrypointsPreferProveoEntrypoint(t *testing.T) {
	t.Parallel()
	root := repoRoot(t)
	paths := []string{
		"defs/opencode/entrypoint.sh",
		"defs/cursor/entrypoint.sh",
		"defs/claudecode/mcp/entrypoint.sh",
	}
	for _, rel := range paths {
		path := filepath.Join(root, rel)
		b, err := os.ReadFile(path)
		if err != nil {
			t.Errorf("read %s: %v", path, err)
			continue
		}
		if !strings.Contains(string(b), "proveo-entrypoint prep") {
			t.Errorf("%s must prefer proveo-entrypoint prep", path)
		}
		if strings.Contains(string(b), "gosu") {
			t.Errorf("%s must never escalate via gosu", path)
		}
	}
}

func TestProviderCursorPin(t *testing.T) {
	t.Parallel()
	got := provider.Detect(func(k string) string {
		if k == "CURSOR_API_KEY" {
			return "sk"
		}
		return ""
	})
	if len(got) != 1 || got[0] != "cursor" {
		t.Fatalf("Detect(CURSOR_API_KEY) = %v, want [cursor]", got)
	}
	acl, ok := provider.ACLBody("cursor")
	if !ok {
		t.Fatal("ACLBody(cursor) missing")
	}
	if !strings.Contains(acl, ".cursor.sh") || !strings.Contains(acl, ".cursor.com") {
		t.Errorf("cursor ACL = %q, want .cursor.sh and .cursor.com", acl)
	}
	r, ok := provider.Resolve("cursor", func(k string) string {
		if k == "CURSOR_API_KEY" {
			return "sk"
		}
		return ""
	})
	if !ok || r.Value == "" {
		t.Fatalf("Resolve(cursor) = %+v ok=%v", r, ok)
	}
}

func TestBrokerSentinelConstant(t *testing.T) {
	t.Parallel()
	if entrypoint.DefaultSentinel != "proveo-brokered" {
		t.Errorf("DefaultSentinel = %q, want proveo-brokered", entrypoint.DefaultSentinel)
	}
}

func TestCursorManifestDeclaresAPIKey(t *testing.T) {
	t.Parallel()
	ms, err := manifest.LoadFS(proveo.Manifests)
	if err != nil {
		t.Fatal(err)
	}
	var cursor *manifest.Manifest
	for i := range ms {
		if ms[i].Name == "cursor" {
			cursor = &ms[i]
			break
		}
	}
	if cursor == nil {
		t.Fatal("cursor manifest missing from embed")
	}
	found := false
	for _, e := range cursor.Env {
		if e.Name == "CURSOR_API_KEY" && e.Secret {
			found = true
			break
		}
	}
	if !found {
		t.Error("cursor manifest must declare CURSOR_API_KEY as secret")
	}
	if !cursor.Dind {
		t.Error("cursor manifest must enable dind (docker client + sibling sidecar offer)")
	}
}

func TestOpenCodeManifestEnablesDind(t *testing.T) {
	t.Parallel()
	ms, err := manifest.LoadFS(proveo.Manifests)
	if err != nil {
		t.Fatal(err)
	}
	for _, m := range ms {
		if m.Name == "opencode" && !m.Dind {
			t.Error("opencode manifest must enable dind")
		}
	}
}
