package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/proveo-ca/proveo/internal/provider"
	"github.com/proveo-ca/proveo/internal/runner"
	"github.com/proveo-ca/proveo/internal/workspace"
)

func TestPickProject(t *testing.T) {
	t.Parallel()
	projs := []workspace.Project{
		{Name: "web", Path: "apps/web"},
		{Name: "util", Path: "packages/util"},
	}
	tests := []struct {
		name  string
		input string
		want  string
	}{
		{name: "first choice", input: "1\n", want: "apps/web"},
		{name: "second choice", input: "2\n", want: "packages/util"},
		{name: "zero is repo root", input: "0\n", want: ""},
		{name: "empty is repo root", input: "\n", want: ""},
		{name: "out of range is repo root", input: "9\n", want: ""},
		{name: "garbage is repo root", input: "xyz\n", want: ""},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got := pickProject(projs, strings.NewReader(tc.input), &strings.Builder{})
			if got != tc.want {
				t.Errorf("pickProject(input=%q) = %q, want %q", tc.input, got, tc.want)
			}
		})
	}
}

// D2 seams — the gating/dispatch/assembly logic that was untestable inside the
// old god-function.

func TestBrokerProvider(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name     string
		mode     string
		detected []string
		on       bool
		want     string
	}{
		{"firewall + 1 provider + on", "firewall", []string{"anthropic"}, true, "anthropic"},
		{"open mode never brokers", "open", []string{"anthropic"}, true, ""},
		{"proxy mode never brokers", "proxy", []string{"anthropic"}, true, ""},
		{"two providers → ambiguous, skip", "firewall", []string{"anthropic", "openai"}, true, ""},
		{"zero providers", "firewall", nil, true, ""},
		{"broker disabled", "firewall", []string{"anthropic"}, false, ""},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := brokerProvider(tc.mode, tc.detected, tc.on); got != tc.want {
				t.Errorf("brokerProvider(%q, %v, %v) = %q, want %q", tc.mode, tc.detected, tc.on, got, tc.want)
			}
		})
	}
}

func TestAssembleAndDispatch(t *testing.T) {
	t.Parallel()

	t.Run("open mode: no lifecycle, bare agent", func(t *testing.T) {
		t.Parallel()
		plan, agent, err := assemble(assembleInput{
			params: runParams{mode: "open", target: "opencode", image: "img"},
			sid:    "s", egDir: "/st", uid: "1000", gid: "1000",
		})
		if err != nil {
			t.Fatal(err)
		}
		if needsLifecycle(plan) {
			t.Error("open (no model) must not need the lifecycle")
		}
		if agent.Image != "img" || agent.User != "1000:1000" || !agent.Interactive {
			t.Errorf("agent config wrong: %+v", agent)
		}
		if strings.Join(agent.ExtraArgs, " ") != strings.Join(plan.AgentArgs, " ") {
			t.Errorf("agent.ExtraArgs must be the plan's AgentArgs")
		}
	})

	t.Run("firewall + provider: full topology through the lifecycle", func(t *testing.T) {
		t.Parallel()
		plan, _, err := assemble(assembleInput{
			params: runParams{mode: "firewall", target: "claudecode", image: "img"},
			sid:    "s", egDir: "/st", uid: "1000", gid: "1000",
			provider: "anthropic", brokerFile: "/st/inject/broker.env",
		})
		if err != nil {
			t.Fatal(err)
		}
		if !needsLifecycle(plan) {
			t.Error("firewall must go through the lifecycle")
		}
		if !plan.UsesSquid || plan.CAWaitPath == "" {
			t.Errorf("firewall plan should use squid + set CAWaitPath: %+v", plan)
		}
	})

	t.Run("open + local model: lifecycle via the ollama sidecar", func(t *testing.T) {
		t.Parallel()
		plan, _, err := assemble(assembleInput{
			params: runParams{mode: "open", target: "opencode", image: "img", localModel: "gemma4"},
			sid:    "s", egDir: "/st", uid: "1000", gid: "1000",
			modelsDir: "/models",
		})
		if err != nil {
			t.Fatal(err)
		}
		if !needsLifecycle(plan) {
			t.Error("open + --local-model must need the lifecycle (ollama sidecar)")
		}
		if plan.OllamaContainer == "" {
			t.Error("local-model plan must set OllamaContainer")
		}
	})

	t.Run("shell + data-dir affect the agent config", func(t *testing.T) {
		t.Parallel()
		_, agent, err := assemble(assembleInput{
			params: runParams{mode: "open", target: "opencode", image: "img", shell: true, dataDir: "/data"},
			sid:    "s", egDir: "/st", uid: "1", gid: "1",
		})
		if err != nil {
			t.Fatal(err)
		}
		if agent.Entrypoint != "bash" {
			t.Errorf("--shell must set Entrypoint=bash, got %q", agent.Entrypoint)
		}
		var found bool
		for _, m := range agent.Mounts {
			if m.Host == "/data" && m.Container == "/workspace/data" && m.ReadOnly {
				found = true
			}
		}
		if !found {
			t.Errorf("--data-dir must add a read-only /workspace/data mount: %+v", agent.Mounts)
		}
	})

	t.Run("declared env is forwarded by bare name, never as KEY=VALUE", func(t *testing.T) {
		t.Parallel()
		_, agent, err := assemble(assembleInput{
			params: runParams{mode: "open", target: "cursor", image: "img"},
			sid:    "s", egDir: "/st", uid: "1", gid: "1",
			env: []string{"CURSOR_API_KEY"},
		})
		if err != nil {
			t.Fatal(err)
		}
		argv := strings.Join(runner.DockerRunArgs(agent), " ")
		if !strings.Contains(argv, "-e CURSOR_API_KEY") {
			t.Errorf("argv must forward the declared env by name: %s", argv)
		}
		if strings.Contains(argv, "CURSOR_API_KEY=") {
			t.Errorf("argv must never contain the env value: %s", argv)
		}
	})

	t.Run("unknown mode errors", func(t *testing.T) {
		t.Parallel()
		if _, _, err := assemble(assembleInput{params: runParams{mode: "nope"}, sid: "s", egDir: "/st"}); err == nil {
			t.Error("assemble with an unknown mode must error")
		}
	})
}

// C6 regression: only the agent's own exit propagates as a bare exit code.
// A failed helper subprocess (docker pull, build.sh) also wraps an
// *exec.ExitError, and swallowing it would exit silently — it must NOT match
// the agent-exit type.
func TestAgentExitDiscrimination(t *testing.T) {
	t.Parallel()
	var ae agentExitError

	if !errors.As(error(agentExitError{code: 42}), &ae) || ae.code != 42 {
		t.Errorf("agentExitError must match itself and carry the code, got %+v", ae)
	}

	// A real wrapped ExitError, as a failed `docker pull` produces.
	cmdErr := exec.Command("false").Run()
	var ee *exec.ExitError
	if !errors.As(cmdErr, &ee) {
		t.Fatalf("exec false should produce an ExitError, got %v", cmdErr)
	}
	wrapped := fmt.Errorf("image unavailable: x (pull failed: %w)", cmdErr)
	if errors.As(wrapped, &ae) {
		t.Error("a wrapped helper ExitError must not be treated as the agent's exit")
	}
}

// T2: writeBrokerEnv writes the injected key to a 0600 file in a 0700 dir, and
// errors when no provider key is present (never writes an empty secret file).
func TestWriteBrokerEnv(t *testing.T) {
	// Isolate from the ambient environment: clear every provider key var.
	for _, k := range provider.KeyVars() {
		t.Setenv(k, "")
	}

	if _, err := writeBrokerEnv(filepath.Join(t.TempDir(), "inject")); err == nil {
		t.Error("writeBrokerEnv with no provider key must error, not write an empty file")
	}

	t.Setenv("ANTHROPIC_API_KEY", "sk-ant-test-value")
	dir := filepath.Join(t.TempDir(), "inject")
	path, err := writeBrokerEnv(dir)
	if err != nil {
		t.Fatal(err)
	}
	fi, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if got := fi.Mode().Perm(); got != 0o600 {
		t.Errorf("broker.env perm = %o, want 600", got)
	}
	di, err := os.Stat(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got := di.Mode().Perm(); got != 0o700 {
		t.Errorf("inject dir perm = %o, want 700", got)
	}
	b, _ := os.ReadFile(path)
	if !strings.Contains(string(b), "ANTHROPIC_API_KEY=sk-ant-test-value") {
		t.Errorf("broker.env content = %q, want the key=value line", b)
	}
}
