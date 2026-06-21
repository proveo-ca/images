#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILURES=()

pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf 'PASS [%d] %s\n' "$TESTS_RUN" "$1"
}

fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("$1")
  printf 'FAIL [%d] %s\n' "$TESTS_RUN" "$1"
  [[ -n "${2:-}" ]] && printf '     %s\n' "$2"
}

assert_file_contains() {
  local desc="$1" file="$2" expected="$3"
  if grep -qF -- "$expected" "$file"; then
    pass "$desc"
  else
    fail "$desc" "Expected '$expected' in $file"
  fi
}

assert_file_not_contains() {
  local desc="$1" file="$2" unexpected="$3"
  if grep -qF -- "$unexpected" "$file"; then
    fail "$desc" "Did not expect '$unexpected' in $file"
  else
    pass "$desc"
  fi
}

assert_executable() {
  local desc="$1" file="$2"
  if [[ -x "$file" ]]; then
    pass "$desc"
  else
    fail "$desc" "$file is not executable"
  fi
}

echo 'Running no-Docker harness contract tests...'

# Shared verification discovery
assert_file_contains "shared verification detector exists" "$ROOT/defs/lib/detect-verify.sh" "detect_verify_commands()"
assert_file_contains "verification detector handles Node projects" "$ROOT/defs/lib/detect-verify.sh" "package.json"
assert_file_contains "verification detector handles Python projects" "$ROOT/defs/lib/detect-verify.sh" "pyproject.toml"
assert_file_contains "verification detector handles Go projects" "$ROOT/defs/lib/detect-verify.sh" "go test ./..."
assert_file_contains "verification detector handles Rust projects" "$ROOT/defs/lib/detect-verify.sh" "cargo test"

DETECT_TMP="$(mktemp -d)"
trap 'rm -rf "$DETECT_TMP"' EXIT
# shellcheck source=/dev/null
source "$ROOT/defs/lib/detect-verify.sh"
cat >"$DETECT_TMP/package.json" <<'JSON'
{"scripts":{"test":"vitest","lint":"eslint .","build":"vite build"}}
JSON
touch "$DETECT_TMP/pnpm-lock.yaml"
NODE_DETECTED="$(detect_verify_commands "$DETECT_TMP")"
if [[ "$NODE_DETECTED" == *"test|pnpm test"* && "$NODE_DETECTED" == *"lint|pnpm lint"* && "$NODE_DETECTED" == *"build|pnpm build"* ]]; then
  pass "verification detector emits pnpm commands for pnpm projects"
else
  fail "verification detector emits pnpm commands for pnpm projects" "Output: $NODE_DETECTED"
fi
rm -f "$DETECT_TMP/package.json" "$DETECT_TMP/pnpm-lock.yaml"
touch "$DETECT_TMP/go.mod"
GO_DETECTED="$(detect_verify_commands "$DETECT_TMP")"
if [[ "$GO_DETECTED" == *"test|go test ./..."* && "$GO_DETECTED" == *"build|go build ./..."* ]]; then
  pass "verification detector emits Go test/build commands"
else
  fail "verification detector emits Go test/build commands" "Output: $GO_DETECTED"
fi
rm -f "$DETECT_TMP/go.mod"

# Claude Code contracts
for variant_entrypoint in "$ROOT/defs/claudecode/mcp/entrypoint.sh" "$ROOT/defs/claudecode/solo/entrypoint.sh"; do
  assert_file_contains "claudecode variant entrypoint keeps dangerous full-consent launch" "$variant_entrypoint" "--dangerously-skip-permissions"
  assert_file_not_contains "claudecode variant entrypoint has no CLAUDE_DANGEROUS opt-out" "$variant_entrypoint" "CLAUDE_DANGEROUS"
  assert_file_contains "claudecode variant entrypoint seeds CLAUDE.md when missing" "$variant_entrypoint" "Seeded CLAUDE.md"
  assert_file_contains "claudecode variant entrypoint supports smoke mode" "$variant_entrypoint" "PROVEO_SMOKE_READY"
done
assert_file_contains "claudecode default prompt encodes verification loop" "$ROOT/defs/claudecode/defaults/CLAUDE.md" "Verification Commands"
assert_file_contains "claudecode run supports open egress mode" "$ROOT/defs/claudecode/run.sh" "open|proxy|inspected-firewall"
assert_file_contains "claudecode parent runner sources shared egress lifecycle" "$ROOT/defs/claudecode/run.sh" 'source "$DEFS_DIR/lib/egress.sh"'
assert_file_contains "claudecode parent runner owns debug shell flow" "$ROOT/defs/claudecode/run.sh" '--shell'
assert_file_contains "claudecode parent runner selects mcp variant image" "$ROOT/defs/claudecode/run.sh" 'PROVEO_CLAUDECODE_IMAGE'
assert_file_contains "claudecode parent runner selects solo variant image" "$ROOT/defs/claudecode/run.sh" 'PROVEO_CLAUDECODE_SOLO_IMAGE'

# OpenCode contracts
assert_file_contains "opencode entrypoint seeds project AGENTS.md" "$ROOT/defs/opencode/entrypoint.sh" "Seeded AGENTS.md"
assert_file_contains "opencode reseeds project AGENTS.md with OPENCODE_RESEED" "$ROOT/defs/opencode/entrypoint.sh" "Re-seeded AGENTS.md"
assert_file_contains "opencode entrypoint reports team workflow" "$ROOT/defs/opencode/entrypoint.sh" "Lead flow: classify"
assert_file_contains "opencode entrypoint bridges ARCHITECT_MODEL" "$ROOT/defs/opencode/entrypoint.sh" "ARCHITECT_MODEL"
assert_file_contains "opencode entrypoint bridges EDITOR_MODEL" "$ROOT/defs/opencode/entrypoint.sh" "EDITOR_MODEL"
assert_file_contains "opencode supports smoke mode" "$ROOT/defs/opencode/entrypoint.sh" "PROVEO_SMOKE_READY"
assert_file_contains "opencode team prompt defines review gates" "$ROOT/defs/opencode/defaults/AGENTS.md" "Review Gates"
assert_file_contains "opencode team prompt defines routing matrix" "$ROOT/defs/opencode/defaults/AGENTS.md" "Routing Matrix"
assert_file_contains "opencode config keeps plan read-only" "$ROOT/defs/opencode/defaults/opencode.json" '"edit": "deny"'
assert_file_contains "opencode config keeps build bash ask" "$ROOT/defs/opencode/defaults/opencode.json" '"bash": "ask"'
assert_file_contains "opencode image bakes shared verification lib" "$ROOT/defs/opencode/Dockerfile" "COPY lib/ /opt/proveo/lib/"
assert_file_contains "opencode build uses defs parent context" "$ROOT/defs/opencode/build.sh" '"$SCRIPT_DIR/.."'

# Cecli contracts
assert_file_contains "cecli entrypoint seeds CONVENTIONS.md" "$ROOT/defs/cecli/entrypoint.sh" "Seeded CONVENTIONS.md"
assert_file_contains "cecli entrypoint bridges ARCHITECT_MODEL" "$ROOT/defs/cecli/entrypoint.sh" "ARCHITECT_MODEL"
assert_file_contains "cecli entrypoint bridges EDITOR_MODEL" "$ROOT/defs/cecli/entrypoint.sh" "EDITOR_MODEL"
assert_file_contains "cecli entrypoint bridges SMALL_MODEL" "$ROOT/defs/cecli/entrypoint.sh" "SMALL_MODEL"
assert_file_contains "cecli supports smoke mode" "$ROOT/defs/cecli/entrypoint.sh" "PROVEO_SMOKE_READY"
assert_file_contains "cecli runtime caps subagents" "$ROOT/defs/cecli/entrypoint.sh" "max_sub_agents"
assert_file_contains "cecli sample keeps auto-commits enabled" "$ROOT/defs/cecli/sample.cecli.conf.yml" "auto-commits: true"
assert_file_contains "cecli sample keeps auto-load disabled" "$ROOT/defs/cecli/sample.cecli.conf.yml" "auto-load: false"
assert_file_contains "cecli sample keeps compaction enabled" "$ROOT/defs/cecli/sample.cecli.conf.yml" "enable-context-compaction: true"
assert_file_contains "cecli conventions keep pair-programming containment" "$ROOT/defs/cecli/defaults/CONVENTIONS.md" "Do not autonomously explore the entire repository"
assert_file_not_contains "cecli conventions do not forbid auto-commit" "$ROOT/defs/cecli/defaults/CONVENTIONS.md" "Never auto-commit"
assert_file_contains "cecli node image bakes local verification lib" "$ROOT/defs/cecli/Dockerfile.node" "COPY proveo-lib/ /opt/proveo/lib/"
assert_file_contains "cecli python image bakes local verification lib" "$ROOT/defs/cecli/Dockerfile.python" "COPY proveo-lib/ /opt/proveo/lib/"
assert_file_contains "cecli local verification lib contains detector" "$ROOT/defs/cecli/proveo-lib/detect-verify.sh" "detect_verify_commands()"
assert_file_contains "cecli build uses local definition context" "$ROOT/defs/cecli/build.sh" '"$SCRIPT_DIR"'

# Build context contracts for Claude variants
assert_file_contains "claudecode mcp image bakes local verification lib" "$ROOT/defs/claudecode/mcp/Dockerfile" "COPY --chown=\${USER_NAME}:\${USER_NAME} proveo-lib/ /opt/proveo/lib/"
assert_file_contains "claudecode solo image bakes local verification lib" "$ROOT/defs/claudecode/solo/Dockerfile" "COPY --chown=\${USER_NAME}:\${USER_NAME} proveo-lib/ /opt/proveo/lib/"
assert_file_contains "claudecode mcp local verification lib contains detector" "$ROOT/defs/claudecode/mcp/proveo-lib/detect-verify.sh" "detect_verify_commands()"
assert_file_contains "claudecode solo local verification lib contains detector" "$ROOT/defs/claudecode/solo/proveo-lib/detect-verify.sh" "detect_verify_commands()"
assert_file_contains "claudecode build uses variant-local context" "$ROOT/defs/claudecode/build.sh" '"$SCRIPT_DIR/$variant"'

# Squid/egress contracts for Claude Code proxy modes
assert_file_contains "shared egress lifecycle is attachable by any agent" "$ROOT/defs/lib/egress.sh" "proveo_egress_prepare()"
assert_file_contains "shared egress lifecycle exposes agent Docker args" "$ROOT/defs/lib/egress.sh" "proveo_egress_append_agent_args()"
assert_file_contains "shared egress lifecycle creates internal networks" "$ROOT/defs/lib/egress.sh" "--internal"
assert_file_contains "shared egress lifecycle starts mitmproxy sidecar" "$ROOT/defs/lib/egress.sh" "proveo_egress_start_mitm"
assert_file_contains "shared egress lifecycle starts Squid sidecar" "$ROOT/defs/lib/egress.sh" "proveo_egress_start_squid"
assert_file_contains "shared egress lifecycle honors PROVEO_KEEP_EGRESS" "$ROOT/defs/lib/egress.sh" "PROVEO_KEEP_EGRESS"
assert_file_contains "squid policy is HTTP/HTTPS protocol allowlist" "$ROOT/defs/sidecars/squid-proxy/squid.conf" "Protocol allowlist: HTTP and HTTPS only"
assert_file_contains "squid policy blocks non-web ports" "$ROOT/defs/sidecars/squid-proxy/squid.conf" "http_access deny !Safe_ports"
assert_file_contains "squid policy allows generic docs/search reads" "$ROOT/defs/sidecars/squid-proxy/squid.conf" "any documentation site, search engine"
assert_file_contains "squid policy includes FireHOL-informed reserved destinations" "$ROOT/defs/sidecars/squid-proxy/squid.conf" "firehol-blocked-nets.conf"
assert_file_contains "squid policy supports optional FireHOL ipset feeds" "$ROOT/defs/sidecars/squid-proxy/squid.conf" "firehol-ipset.conf"
assert_file_contains "reserved destination blocklist blocks metadata IP range" "$ROOT/defs/sidecars/squid-proxy/firehol-blocked-nets.conf" "169.254.0.0/16"
assert_file_contains "optional FireHOL updater fetches firehol_level1 by default" "$ROOT/defs/sidecars/squid-proxy/update-firehol-ipsets.sh" "firehol_level1"
assert_file_contains "optional FireHOL updater generates Squid dst ACLs" "$ROOT/defs/sidecars/squid-proxy/update-firehol-ipsets.sh" "acl firehol_ipset dst"
assert_executable "FireHOL updater is executable" "$ROOT/defs/sidecars/squid-proxy/update-firehol-ipsets.sh"
assert_executable "squid run wrapper is executable" "$ROOT/defs/sidecars/squid-proxy/run.sh"
assert_file_contains "mitmproxy image uses dedicated entrypoint" "$ROOT/defs/sidecars/mitmproxy/Dockerfile" 'ENTRYPOINT ["/entrypoint.sh"]'
assert_file_contains "mitmproxy image builds on the official mitmproxy base" "$ROOT/defs/sidecars/mitmproxy/Dockerfile" "FROM mitmproxy/mitmproxy"
assert_file_contains "mitmproxy entrypoint chains to a Squid upstream proxy" "$ROOT/defs/sidecars/mitmproxy/entrypoint.sh" 'upstream:${PROVEO_MITM_UPSTREAM}'
assert_file_contains "mitmproxy entrypoint loads the NDJSON flow addon" "$ROOT/defs/sidecars/mitmproxy/entrypoint.sh" "-s /addons/ndjson_dump.py"
assert_file_contains "egress lifecycle points mitmproxy at the Squid upstream" "$ROOT/defs/lib/egress.sh" "PROVEO_MITM_UPSTREAM=http://squid:3128"
assert_file_contains "egress lifecycle trusts the mitmproxy CA in the agent" "$ROOT/defs/lib/egress.sh" "NODE_EXTRA_CA_CERTS=/etc/proveo/mitmproxy-ca-cert.pem"
assert_file_contains "egress lifecycle can attach an Ollama local-model sidecar" "$ROOT/defs/lib/egress.sh" "proveo_egress_start_ollama"
assert_file_contains "egress lifecycle serves host models read-only to the sidecar" "$ROOT/defs/lib/egress.sh" ":/models:ro"
assert_file_contains "egress lifecycle keeps the local model off the egress proxy" "$ROOT/defs/lib/egress.sh" "NO_PROXY=ollama,localhost,127.0.0.1"
assert_file_contains "egress lifecycle assigns the local model via the model bridge" "$ROOT/defs/lib/egress.sh" 'ARCHITECT_MODEL=ollama/'
assert_file_contains "claudecode run exposes a local-model flag" "$ROOT/defs/claudecode/run.sh" "--local-model"
assert_file_contains "egress lifecycle reports egress after the container exits" "$ROOT/defs/lib/egress.sh" "proveo_egress_report"
assert_file_contains "egress cleanup triggers the post-run report" "$ROOT/defs/lib/egress.sh" "proveo_egress_report || true"
assert_file_contains "egress report ranks the top 5 allowed operations" "$ROOT/defs/lib/egress.sh" "Top 5 ALLOWED"
assert_file_contains "egress report ranks the top 5 denied operations" "$ROOT/defs/lib/egress.sh" "Top 5 DENIED"
assert_file_contains "egress preflights all sidecar images before docker run" "$ROOT/defs/lib/egress.sh" "proveo_egress_ensure_images"
assert_file_contains "egress preflight builds local proveo images, pulls the rest" "$ROOT/defs/lib/egress.sh" "image not built"
assert_file_contains "egress prepare fails fast when an image is not ready" "$ROOT/defs/lib/egress.sh" "egress preflight failed"
assert_file_contains "egress sidecar start checks the docker run exit code" "$ROOT/defs/lib/egress.sh" "failed to start Squid sidecar"
assert_file_contains "egress tests reuse the shared image preflight (dedupe)" "$ROOT/defs/claudecode/tests/test_egress.sh" "proveo_egress_ensure_image"

# Provider allowlist (pin model-provider egress; auto-detected from API keys)
assert_file_contains "squid.conf includes the provider allowlist" "$ROOT/defs/sidecars/squid-proxy/squid.conf" "include /etc/squid/provider-allow.conf"
assert_file_contains "egress auto-detects the provider from the present API key" "$ROOT/defs/lib/egress.sh" "proveo_egress_detect_providers"
assert_file_contains "egress maps trusted first-party APIs (anthropic)" "$ROOT/defs/lib/egress.sh" "anthropic)"
assert_file_contains "egress maps GMI Cloud inference endpoint" "$ROOT/defs/lib/egress.sh" ".gmi-serving.com"
assert_file_contains "egress scopes hyperscaler endpoints tightly (bedrock regex)" "$ROOT/defs/lib/egress.sh" "bedrock-runtime"
assert_file_contains "provider pin governs writes, not reads (no deny-all)" "$ROOT/defs/lib/egress.sh" "http_access allow unsafe_methods provider_allow"
assert_file_not_contains "provider pin never blocks web reads (no lockdown deny-all)" "$ROOT/defs/lib/egress.sh" "http_access deny all"
assert_file_not_contains "no lockdown option remains" "$ROOT/defs/lib/egress.sh" "PROVEO_EGRESS_LOCKDOWN"
assert_executable "provider allowlist updater is executable" "$ROOT/defs/sidecars/squid-proxy/update-provider-allow.sh"
assert_file_contains "provider updater reconciles against LiteLLM registry" "$ROOT/defs/sidecars/squid-proxy/update-provider-allow.sh" "litellm"
assert_file_contains "provider updater is non-destructive (reports drift)" "$ROOT/defs/sidecars/squid-proxy/update-provider-allow.sh" "provider-coverage.txt"

# Observability contracts
assert_file_contains "egress dashboard parses mitmproxy NDJSON flows" "$ROOT/defs/egress-dashboard/server.js" "parseMitmNdjson"
assert_file_contains "egress dashboard parses Squid access logs" "$ROOT/defs/egress-dashboard/server.js" "parseSquidAccess"
assert_file_contains "egress dashboard parses guard reject logs" "$ROOT/defs/egress-dashboard/server.js" "parseGuardLog"
assert_file_contains "egress dashboard exposes normalized events" "$ROOT/defs/egress-dashboard/server.js" "/api/events"

echo
printf 'Tests run: %d\n' "$TESTS_RUN"
printf 'Passed:    %d\n' "$TESTS_PASSED"
printf 'Failed:    %d\n' "$TESTS_FAILED"

if (( TESTS_FAILED > 0 )); then
  printf '\nFailed tests:\n'
  for failure in "${FAILURES[@]}"; do
    printf '  - %s\n' "$failure"
  done
  exit 1
fi

echo 'All no-Docker harness contract tests passed.'
