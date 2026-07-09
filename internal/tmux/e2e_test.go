//go:build e2e

// SPEC: _spec/tests/40-agent-e2e-components.puml, _spec/tests/41-agent-e2e-sequence.puml

package tmux_test

import (
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/proveo-ca/proveo/internal/tmux"
)

// TestPromptfulE2E is the reference agent-E2E ("promptful") test from
// _spec/testing.md: it drives a real harness TUI, headlessly via tmux, through a
// one-step task backed by a LOCAL model (Ollama), and asserts the SIDE EFFECT
// (a file), not the model's prose. Gated + skips unless the whole stack is
// present, so it never fails CI for missing local infra.
//
//	PROVEO_LLM_TEST=1 [PROVEO_TEST_TARGET=opencode] [PROVEO_TEST_LOCAL_MODEL=gemma4] \
//	  go test -tags=e2e ./internal/tmux/ -run PromptfulE2E -v -timeout 360s
func TestPromptfulE2E(t *testing.T) {
	if os.Getenv("PROVEO_LLM_TEST") != "1" {
		t.Skip("set PROVEO_LLM_TEST=1 to run the local-model agent E2E")
	}
	if !tmux.Available() {
		t.Skip("tmux not installed (brew install tmux)")
	}
	if _, err := exec.LookPath("docker"); err != nil {
		t.Skip("docker not available")
	}
	target := env("PROVEO_TEST_TARGET", "opencode")
	image := env("PROVEO_TEST_IMAGE", "proveo/"+target+":latest")
	if !dockerImagePresent(t, image) {
		t.Skipf("harness image %s not built", image)
	}
	model := env("PROVEO_TEST_LOCAL_MODEL", "gemma4")
	if !ollamaHasModel(model) {
		t.Skipf("Ollama model %q not available on the host", model)
	}

	proveoBin := buildProveo(t)
	work := t.TempDir()
	mustRun(t, work, "git", "init", "-q", ".")

	// The task's success is a binary, prose-independent side effect.
	const marker = "BANANA-E2E-OK"
	prompt := fmt.Sprintf("Create a file named DONE.txt in the current directory containing exactly the text %s and nothing else, then stop.", marker)

	sess := tmux.New(fmt.Sprintf("proveo-e2e-%d", os.Getpid()), nil)
	t.Cleanup(sess.Kill)

	// Broker mode + --local-model: the agent reaches gemma4 via the Ollama sidecar
	// (NO_PROXY), no cloud key. tmux gives the -it TUI a headless PTY.
	if err := sess.Start(200, 50, proveoBin, "run", target,
		"--egress-mode", "broker", "--local-model", model, "--input", work); err != nil {
		t.Fatalf("start session: %v", err)
	}

	// Wait for the harness to be interactive, then send the task.
	if _, err := sess.WaitFor(env("PROVEO_TEST_READY", ">"), 90*time.Second); err != nil {
		cap, _ := sess.Capture()
		t.Fatalf("harness did not become ready: %v\n--- screen ---\n%s", err, cap)
	}
	if err := sess.SendText(prompt); err != nil {
		t.Fatal(err)
	}
	if err := sess.Enter(); err != nil {
		t.Fatal(err)
	}

	// Assert the SIDE EFFECT (poll the host-side file), not the screen text.
	donePath := filepath.Join(work, "DONE.txt")
	deadline := time.Now().Add(4 * time.Minute)
	for {
		if b, err := os.ReadFile(donePath); err == nil && strings.Contains(string(b), marker) {
			return // success
		}
		if time.Now().After(deadline) {
			cap, _ := sess.Capture()
			t.Fatalf("agent did not produce DONE.txt containing %q in time\n--- screen ---\n%s", marker, cap)
		}
		time.Sleep(3 * time.Second)
	}
}

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func mustRun(t *testing.T, dir string, name string, args ...string) {
	t.Helper()
	c := exec.Command(name, args...)
	c.Dir = dir
	if out, err := c.CombinedOutput(); err != nil {
		t.Fatalf("%s %v: %v\n%s", name, args, err, out)
	}
}

func dockerImagePresent(t *testing.T, image string) bool {
	t.Helper()
	return exec.Command("docker", "image", "inspect", image).Run() == nil
}

func ollamaHasModel(model string) bool {
	resp, err := http.Get("http://localhost:11434/api/tags")
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	buf := make([]byte, 1<<16)
	n, _ := resp.Body.Read(buf)
	// Match "gemma4" against "gemma4:latest" etc.
	return strings.Contains(string(buf[:n]), strings.SplitN(model, ":", 2)[0])
}

func buildProveo(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	repoRoot := filepath.Join(wd, "..", "..")
	bin := filepath.Join(t.TempDir(), "proveo")
	c := exec.Command("go", "build", "-o", bin, "./cmd/proveo")
	c.Dir = repoRoot
	if out, err := c.CombinedOutput(); err != nil {
		t.Fatalf("build proveo: %v\n%s", err, out)
	}
	return bin
}
