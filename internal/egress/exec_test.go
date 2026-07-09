package egress

import (
	"errors"
	"strings"
	"testing"
	"time"
)

// scriptedRunner fails its Run the first failN times, then succeeds.
type scriptedRunner struct {
	failN int
	calls int
}

func (s *scriptedRunner) Run(args ...string) (string, error) {
	s.calls++
	if s.calls <= s.failN {
		return "", errors.New("not ready")
	}
	return "", nil
}

func TestWaitOllamaReady(t *testing.T) {
	old := ollamaPollInterval
	ollamaPollInterval = time.Millisecond
	t.Cleanup(func() { ollamaPollInterval = old })

	t.Run("returns once the sidecar answers", func(t *testing.T) {
		r := &scriptedRunner{failN: 2}
		if err := WaitOllamaReady(r, "sess-ollama", time.Second); err != nil {
			t.Fatalf("WaitOllamaReady: %v", err)
		}
		if r.calls != 3 {
			t.Errorf("want 3 polls (2 fail + 1 ok), got %d", r.calls)
		}
	})

	t.Run("times out when never ready", func(t *testing.T) {
		r := &scriptedRunner{failN: 1 << 30}
		if err := WaitOllamaReady(r, "sess-ollama", 5*time.Millisecond); err == nil {
			t.Fatal("want timeout error, got nil")
		}
	})
}

// netRunner fails `network rm` failN times (simulating the async-endpoint race),
// succeeds everything else, and records every call.
type netRunner struct {
	failN int
	netrm int
	calls []string
}

func (n *netRunner) Run(args ...string) (string, error) {
	n.calls = append(n.calls, strings.Join(args, " "))
	if len(args) >= 2 && args[0] == "network" && args[1] == "rm" {
		n.netrm++
		if n.netrm <= n.failN {
			return "", errors.New("has active endpoints")
		}
	}
	return "", nil
}

func TestTeardownRetriesNetworkRm(t *testing.T) {
	oldI := teardownNetInterval
	teardownNetInterval = time.Millisecond
	t.Cleanup(func() { teardownNetInterval = oldI })

	p := Plan{Cleanup: []Command{{"rm", "-f", "sess-ollama"}, {"network", "rm", "sess-net"}}}
	r := &netRunner{failN: 2} // fails twice, then the endpoint drains
	p.Teardown(r)

	if r.netrm != 3 {
		t.Errorf("want 3 network-rm attempts (2 fail + 1 ok), got %d; calls=%v", r.netrm, r.calls)
	}
	if r.calls[0] != "rm -f sess-ollama" {
		t.Errorf("container must be removed before its network; calls=%v", r.calls)
	}
}

func TestTeardownGivesUpAfterBudget(t *testing.T) {
	oldI := teardownNetInterval
	teardownNetInterval = time.Millisecond
	t.Cleanup(func() { teardownNetInterval = oldI })

	p := Plan{Cleanup: []Command{{"network", "rm", "sess-net"}}}
	r := &netRunner{failN: 1 << 30} // never drains
	p.Teardown(r)                   // must return, not hang

	if want := teardownNetRetries + 1; r.netrm != want {
		t.Errorf("want %d bounded attempts, got %d", want, r.netrm)
	}
}
