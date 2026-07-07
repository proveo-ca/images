package egressproxy

import (
	"errors"
	"net/http"
	"testing"

	"github.com/proveo-ca/proveo/internal/egresspolicy"
)

// TestPolicyModifierBlocks checks the glue between the policy decision and
// martian: a blocked decision returns an error (fail closed), an allowed one
// does not. A nil recorder must be a safe no-op.
func TestPolicyModifierBlocks(t *testing.T) {
	pol := egresspolicy.New(egresspolicy.Config{
		WriteHosts: []string{"api.github.com"},
		DenySinks:  []string{"webhook.site"},
	})
	m := policyModifier{pol: pol, rec: nil}

	cases := []struct {
		name      string
		method    string
		url       string
		wantBlock bool
	}{
		{"read off-provider allowed", "GET", "https://docs.example.com/x", false},
		{"write off-allowlist blocked", "POST", "https://evil.com/x", true},
		{"write to allowlisted host allowed", "POST", "https://api.github.com/x", false},
		{"read to sink blocked", "GET", "https://webhook.site/abc", true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req, err := http.NewRequest(tc.method, tc.url, nil)
			if err != nil {
				t.Fatal(err)
			}
			gotBlock := m.ModifyRequest(req) != nil
			if gotBlock != tc.wantBlock {
				t.Errorf("ModifyRequest block=%v, want %v", gotBlock, tc.wantBlock)
			}
		})
	}
}

func TestReqChainStopsOnFirstError(t *testing.T) {
	var ran int
	count := reqModFunc(func(*http.Request) error { ran++; return nil })
	boom := reqModFunc(func(*http.Request) error { ran++; return errors.New("boom") })
	chain := reqChain{count, boom, count}
	req, _ := http.NewRequest("GET", "https://x.com/", nil)
	if err := chain.ModifyRequest(req); err == nil {
		t.Fatal("chain must surface the modifier error")
	}
	if ran != 2 { // first (ok) + second (boom); third must not run
		t.Errorf("chain ran %d modifiers, want 2 (stops on first error)", ran)
	}
}

type reqModFunc func(*http.Request) error

func (f reqModFunc) ModifyRequest(req *http.Request) error { return f(req) }
