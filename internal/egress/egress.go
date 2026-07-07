// SPEC: _spec/defs/claudecode/claudecode-egress-topology.puml
//
// Package egress holds the egress-lifecycle policy logic being ported from
// defs/lib/egress.sh (Plan 4 Phase 2): provider detection and the Squid
// write-pin allowlist. It is the Go source of truth; egress.sh delegates to the
// `proveo-egress` subcommands when PROVEO_EGRESS_BIN is set, else uses its Bash
// fallback (behavior parity is asserted by tests).
package egress

import (
	"strings"

	"github.com/proveo-ca/proveo/internal/provider"
)

// ProviderAllowConf renders the Squid `provider-allow.conf` include for the
// given provider(s), mirroring `proveo_egress_write_provider_allow`. It pins the
// visible write methods (POST/...) to only those providers' endpoints; every
// other host stays write-denied by squid.conf. customDomains (space-separated),
// when set, adds an extra dstdomain ACL. Returns the file content plus the
// matched and unknown provider names.
func ProviderAllowConf(providers []string, customDomains string) (conf string, matched, unknown []string) {
	providers = normalize(providers)
	customDomains = strings.TrimSpace(customDomains)
	if len(providers) == 0 && customDomains == "" {
		return "# No provider allowlist active (no provider pinned or API key detected).\n", nil, nil
	}

	var b strings.Builder
	if len(providers) > 0 {
		b.WriteString("# Provider allowlist — resolved provider(s): " + strings.Join(providers, " ") + "\n")
	} else {
		b.WriteString("# Provider allowlist — custom domains only.\n")
	}
	for _, p := range providers {
		if body, ok := provider.ACLBody(p); ok {
			b.WriteString("acl provider_allow " + body + "\n")
			matched = append(matched, p)
		} else {
			unknown = append(unknown, p)
		}
	}
	if customDomains != "" {
		b.WriteString("acl provider_allow dstdomain " + customDomains + "\n")
		matched = append(matched, "custom")
	}
	b.WriteString("http_access allow unsafe_methods provider_allow\n")
	return b.String(), matched, unknown
}

// normalize splits comma/space-separated tokens and drops blanks, so callers can
// pass "anthropic,openai" or []string{"anthropic openai"} interchangeably.
func normalize(in []string) []string {
	var out []string
	for _, tok := range in {
		for _, f := range strings.FieldsFunc(tok, func(r rune) bool { return r == ',' || r == ' ' || r == '\t' }) {
			if f != "" {
				out = append(out, f)
			}
		}
	}
	return out
}
