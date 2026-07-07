package egress

import (
	"flag"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

var update = flag.Bool("update", false, "update golden files")

func baseOpts(mode string) Options {
	return Options{
		Mode: mode, SessionID: "proveo-sess", AgentName: "claudecode-mcp",
		UID: "1000", GID: "1000", ModelsDir: "/home/tester/.ollama/models",
		ConfDir: "/state/mitmproxy/confdir", FlowsDir: "/state/mitmproxy/flows",
		SquidConfigDir: "/state/squid/config", SquidLogDir: "/state/squid/logs",
	}
}

func TestBuildPlanGolden(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name string
		opts Options
	}{
		{name: "open", opts: baseOpts("open")},
		{name: "open_local_model", opts: withModel(baseOpts("open"), "gemma4")},
		{name: "proxy", opts: baseOpts("proxy")},
		{name: "firewall", opts: baseOpts("firewall")},
		{name: "firewall_broker", opts: withBroker(baseOpts("firewall"), "anthropic", "/state/inject/broker.env")},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			p, err := BuildPlan(tc.opts)
			if err != nil {
				t.Fatalf("BuildPlan(%s): unexpected error: %v", tc.name, err)
			}
			got := p.Render()
			golden := filepath.Join("testdata", tc.name+".golden")
			if *update {
				if err := os.WriteFile(golden, []byte(got), 0o644); err != nil {
					t.Fatal(err)
				}
			}
			want, err := os.ReadFile(golden)
			if err != nil {
				t.Fatalf("reading golden %s (run with -update to create): %v", golden, err)
			}
			if got != string(want) {
				t.Errorf("BuildPlan(%s) mismatch with %s (-update to refresh):\n--- got ---\n%s", tc.name, golden, got)
			}
		})
	}
}

func withModel(o Options, m string) Options { o.LocalModel = m; return o }
func withBroker(o Options, p, f string) Options {
	o.Provider = p
	o.BrokerEnvFile = f
	return o
}

func TestBuildPlanUnknownMode(t *testing.T) {
	t.Parallel()
	if _, err := BuildPlan(Options{Mode: "nope"}); err == nil {
		t.Fatal("BuildPlan(mode=nope) = nil error, want error")
	}
}

func TestModesAndValidMode(t *testing.T) {
	t.Parallel()
	if got := Modes(); len(got) != 3 || got[0] != "open" || got[1] != "proxy" || got[2] != "firewall" {
		t.Errorf("Modes() = %v, want [open proxy firewall]", got)
	}
	for _, m := range Modes() {
		if !ValidMode(m) {
			t.Errorf("ValidMode(%q) = false for a listed mode", m)
		}
	}
	if ValidMode("nope") || ValidMode("") {
		t.Error("ValidMode must reject unknown/empty modes")
	}
}

// Security invariants — these assert properties, not exact strings.
func TestBuildPlanInvariants(t *testing.T) {
	t.Parallel()

	t.Run("open mode adds no proxy env and no internal network", func(t *testing.T) {
		t.Parallel()
		p, _ := BuildPlan(baseOpts("open"))
		if joined := strings.Join(p.AgentArgs, " "); strings.Contains(joined, "HTTP_PROXY") {
			t.Errorf("open AgentArgs should not set a proxy, got %q", joined)
		}
		if len(p.Networks) != 0 {
			t.Errorf("open (no model) should create no networks, got %v", p.Networks)
		}
	})

	t.Run("proxy+firewall agent networks are --internal; only egress net is not", func(t *testing.T) {
		t.Parallel()
		for _, mode := range []string{"proxy", "firewall"} {
			p, _ := BuildPlan(baseOpts(mode))
			for _, n := range p.Networks {
				j := strings.Join(n, " ")
				isEgress := strings.Contains(j, "squid-egress-net")
				isInternal := strings.Contains(j, "--internal")
				if isEgress && isInternal {
					t.Errorf("%s: egress network must be internet-capable (not --internal): %q", mode, j)
				}
				if !isEgress && !isInternal {
					t.Errorf("%s: non-egress network must be --internal: %q", mode, j)
				}
			}
		}
	})

	t.Run("firewall mode trusts the mitm CA and waits for it", func(t *testing.T) {
		t.Parallel()
		p, _ := BuildPlan(baseOpts("firewall"))
		j := strings.Join(p.AgentArgs, " ")
		for _, v := range []string{"SSL_CERT_FILE=", "NODE_EXTRA_CA_CERTS=", "INSPECT_PROXY=http://mitm:8888"} {
			if !strings.Contains(j, v) {
				t.Errorf("firewall AgentArgs missing %q; got %q", v, j)
			}
		}
		if p.CAWaitPath == "" {
			t.Error("firewall plan must set CAWaitPath")
		}
	})

	t.Run("broker wires provider + env-file into the proxy sidecar", func(t *testing.T) {
		t.Parallel()
		p, _ := BuildPlan(withBroker(baseOpts("firewall"), "anthropic", "/state/inject/broker.env"))
		var proxy string
		for _, c := range p.Sidecars {
			if strings.Contains(strings.Join(c, " "), "proveo/egress-proxy") {
				proxy = strings.Join(c, " ")
			}
		}
		if !strings.Contains(proxy, "PROVEO_EGRESS_PROVIDER=anthropic") {
			t.Errorf("proxy sidecar missing provider env; got %q", proxy)
		}
		if !strings.Contains(proxy, "/broker:ro") {
			t.Errorf("proxy sidecar missing broker env-file mount; got %q", proxy)
		}
	})

	t.Run("proxy+firewall blackhole external DNS on the agent", func(t *testing.T) {
		t.Parallel()
		for _, mode := range []string{"proxy", "firewall"} {
			p, _ := BuildPlan(baseOpts(mode))
			if j := strings.Join(p.AgentArgs, " "); !strings.Contains(j, "--dns 0.0.0.0") {
				t.Errorf("%s: agent must blackhole external DNS (--dns 0.0.0.0); got %q", mode, j)
			}
		}
		// open mode must NOT blackhole DNS (it has no proxy to resolve for it).
		p, _ := BuildPlan(baseOpts("open"))
		if strings.Contains(strings.Join(p.AgentArgs, " "), "--dns") {
			t.Error("open mode must not set --dns")
		}
	})

	t.Run("local model bypasses the proxy via NO_PROXY", func(t *testing.T) {
		t.Parallel()
		p, _ := BuildPlan(withModel(baseOpts("firewall"), "gemma4"))
		if j := strings.Join(p.AgentArgs, " "); !strings.Contains(j, "NO_PROXY=ollama") {
			t.Errorf("local-model AgentArgs must set NO_PROXY for ollama; got %q", j)
		}
	})

	t.Run("local model mounts host models read-only and sets the readiness wait", func(t *testing.T) {
		t.Parallel()
		p, _ := BuildPlan(withModel(baseOpts("open"), "gemma4"))
		var ollama string
		for _, c := range p.Sidecars {
			if strings.Contains(strings.Join(c, " "), "--network-alias ollama") {
				ollama = strings.Join(c, " ")
			}
		}
		if !strings.Contains(ollama, ":/models:ro") {
			t.Errorf("ollama sidecar must bind-mount host models read-only; got %q", ollama)
		}
		if p.OllamaContainer == "" {
			t.Error("local-model plan must set OllamaContainer for the readiness wait")
		}
	})

	t.Run("no ModelsDir means no mount", func(t *testing.T) {
		t.Parallel()
		o := withModel(baseOpts("open"), "gemma4")
		o.ModelsDir = ""
		p, _ := BuildPlan(o)
		if j := strings.Join(p.Sidecars[0], " "); strings.Contains(j, ":/models:ro") {
			t.Errorf("empty ModelsDir must emit no mount; got %q", j)
		}
	})
}

// fakeRunner records the docker invocations for Apply/Teardown tests.
type fakeRunner struct{ calls []string }

func (f *fakeRunner) Run(args ...string) (string, error) {
	f.calls = append(f.calls, strings.Join(args, " "))
	return "", nil
}

func TestApplyOrder(t *testing.T) {
	t.Parallel()
	p, _ := BuildPlan(baseOpts("firewall"))
	var fr fakeRunner
	if err := p.Apply(&fr); err != nil {
		t.Fatalf("Apply: %v", err)
	}
	// Networks must be created before sidecars run.
	firstRun, firstNet := -1, -1
	for i, c := range fr.calls {
		if strings.HasPrefix(c, "network create") && firstNet == -1 {
			firstNet = i
		}
		if strings.HasPrefix(c, "run -d") && firstRun == -1 {
			firstRun = i
		}
	}
	if firstNet == -1 || firstRun == -1 || firstNet > firstRun {
		t.Errorf("networks must be created before sidecars: netIdx=%d runIdx=%d calls=%v", firstNet, firstRun, fr.calls)
	}
}
