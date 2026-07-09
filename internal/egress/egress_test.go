package egress

import (
	"strings"
	"testing"
)

func TestProviderAllowNoProviders(t *testing.T) {
	conf, matched, unknown := ProviderAllowConf(nil, "")
	if !strings.HasPrefix(conf, "# No provider allowlist active") {
		t.Fatalf("empty providers should be a no-op comment, got:\n%s", conf)
	}
	if len(matched) != 0 || len(unknown) != 0 {
		t.Fatalf("matched=%v unknown=%v, want both empty", matched, unknown)
	}
}

func TestProviderAllowAnthropic(t *testing.T) {
	conf, matched, unknown := ProviderAllowConf([]string{"anthropic"}, "")
	wantLines := []string{
		"# Provider allowlist — resolved provider(s): anthropic",
		"acl provider_allow dstdomain .anthropic.com",
		"http_access allow unsafe_methods provider_allow",
	}
	for _, l := range wantLines {
		if !strings.Contains(conf, l) {
			t.Errorf("conf missing line %q; got:\n%s", l, conf)
		}
	}
	if len(matched) != 1 || matched[0] != "anthropic" || len(unknown) != 0 {
		t.Fatalf("matched=%v unknown=%v", matched, unknown)
	}
}

func TestProviderAllowBedrockScopedNotAllOfAWS(t *testing.T) {
	// The confirmed HIGH: bedrock must be scoped to bedrock-runtime, never all of
	// .amazonaws.com. This asserts parity with the contract-suite expectation.
	conf, _, _ := ProviderAllowConf([]string{"bedrock"}, "")
	if !strings.Contains(conf, `dstdom_regex (^|\.)bedrock-runtime\.[a-z0-9-]+\.amazonaws\.com$`) {
		t.Fatalf("bedrock ACL not scoped to bedrock-runtime:\n%s", conf)
	}
	if strings.Contains(conf, "dstdomain .amazonaws.com") || strings.Contains(conf, "dstdomain amazonaws.com") {
		t.Fatalf("bedrock must NOT allow all of amazonaws.com:\n%s", conf)
	}
}

func TestProviderAllowCustomDomains(t *testing.T) {
	conf, matched, _ := ProviderAllowConf([]string{"anthropic"}, ".myhost.internal")
	if !strings.Contains(conf, "acl provider_allow dstdomain .myhost.internal") {
		t.Fatalf("custom domain not added:\n%s", conf)
	}
	found := false
	for _, m := range matched {
		if m == "custom" {
			found = true
		}
	}
	if !found {
		t.Fatalf("custom not in matched: %v", matched)
	}
}

// C1 regression: custom domains must be honored even when NO named provider is
// pinned (previously an early return dropped them).
func TestProviderAllowCustomDomainsOnly(t *testing.T) {
	conf, matched, unknown := ProviderAllowConf(nil, ".myhost.internal")
	if !strings.Contains(conf, "acl provider_allow dstdomain .myhost.internal") {
		t.Fatalf("custom-only domain dropped when no provider pinned:\n%s", conf)
	}
	if !strings.Contains(conf, "http_access allow unsafe_methods provider_allow") {
		t.Errorf("custom-only conf missing the http_access allow line:\n%s", conf)
	}
	if len(unknown) != 0 {
		t.Errorf("unexpected unknown providers: %v", unknown)
	}
	if len(matched) != 1 || matched[0] != "custom" {
		t.Errorf("matched = %v, want [custom]", matched)
	}
}

func TestProviderAllowUnknown(t *testing.T) {
	conf, matched, unknown := ProviderAllowConf([]string{"anthropic", "madeup"}, "")
	if len(matched) != 1 || matched[0] != "anthropic" {
		t.Fatalf("matched=%v, want [anthropic]", matched)
	}
	if len(unknown) != 1 || unknown[0] != "madeup" {
		t.Fatalf("unknown=%v, want [madeup]", unknown)
	}
	// The header comment echoes all requested providers (parity with Bash), but
	// an unknown provider must never produce an `acl provider_allow` line.
	if n := strings.Count(conf, "acl provider_allow "); n != 1 {
		t.Fatalf("want exactly 1 ACL line (anthropic), got %d:\n%s", n, conf)
	}
}

func TestNormalizeAcceptsCommaAndSpace(t *testing.T) {
	conf, matched, _ := ProviderAllowConf([]string{"anthropic,openai"}, "")
	if len(matched) != 2 {
		t.Fatalf("comma-separated not split: matched=%v", matched)
	}
	if !strings.Contains(conf, ".anthropic.com") || !strings.Contains(conf, ".openai.com") {
		t.Fatalf("both providers should appear:\n%s", conf)
	}
}
