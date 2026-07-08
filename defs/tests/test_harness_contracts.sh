#!/usr/bin/env bash
# SPEC: _spec/tests/20-contract.puml
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

# Runtime user contracts (containers always run as the invoking host user, root-free)
assert_file_contains "entrypoint lib defines the generic runtime-user helper" "$ROOT/packages/lib/entrypoint-lib.sh" "ensure_runtime_user()"
assert_file_contains "runtime-user helper never requires root (degrades gracefully)" "$ROOT/packages/lib/entrypoint-lib.sh" "export HOME=/tmp"
for harness_entrypoint in \
  "$ROOT/defs/claudecode/mcp/entrypoint.sh" \
  "$ROOT/defs/claudecode/solo/entrypoint.sh" \
  "$ROOT/defs/opencode/entrypoint.sh" \
  "$ROOT/defs/cursor/entrypoint.sh" \
  "$ROOT/defs/cecli/entrypoint.sh"; do
  assert_file_contains "${harness_entrypoint#$ROOT/defs/} makes the run-as uid usable" "$harness_entrypoint" "ensure_runtime_user"
  assert_file_not_contains "${harness_entrypoint#$ROOT/defs/} never escalates via gosu" "$harness_entrypoint" "gosu"
done
assert_file_contains "claudecode wrapper runs container as invoking host user" "$ROOT/defs/claudecode/run.sh" '"--user" "$(id -u):$(id -g)"'
assert_file_contains "opencode wrapper runs container as invoking host user" "$ROOT/defs/opencode/run.sh" '"--user" "$(id -u):$(id -g)"'
assert_file_contains "cursor wrapper runs container as invoking host user" "$ROOT/defs/cursor/run.sh" '"--user" "$(id -u):$(id -g)"'
assert_file_contains "cecli wrapper runs container as invoking host user" "$ROOT/defs/cecli/run.sh" '"--user" "$(id -u):$(id -g)"'
assert_file_contains "distributable CLI runs containers as invoking host user" "$ROOT/apps/cli/public/cli/lib/runners.sh" '--user "$(id -u):$(id -g)"'
assert_file_not_contains "cecli wrapper no longer passes LOCAL_UID" "$ROOT/defs/cecli/run.sh" "LOCAL_UID"
assert_file_not_contains "distributable CLI no longer passes LOCAL_UID" "$ROOT/apps/cli/public/cli/lib/runners.sh" "LOCAL_UID"
assert_file_not_contains "cecli node image ships no gosu" "$ROOT/defs/cecli/Dockerfile.node" "gosu"
assert_file_not_contains "cecli python image ships no gosu" "$ROOT/defs/cecli/Dockerfile.python" "gosu"
assert_file_contains "cecli node image defaults to a non-root user" "$ROOT/defs/cecli/Dockerfile.node" 'USER ${USER_NAME}'
assert_file_contains "cecli python image defaults to a non-root user" "$ROOT/defs/cecli/Dockerfile.python" 'USER ${USER_NAME}'
assert_file_contains "cursor image defaults to a non-root user" "$ROOT/defs/cursor/Dockerfile" 'USER ${USER_NAME}'
assert_file_contains "cursor image bakes the shared uid-1000 user block" "$ROOT/defs/cursor/Dockerfile" 'ARG USER_ID=1000'
assert_file_not_contains "cursor image ships no gosu" "$ROOT/defs/cursor/Dockerfile" "gosu"

# Contribution guideline: the runtime user boundary is documented for new defs
assert_file_contains "contribution guideline exists and mandates host-uid launch" "$ROOT/CONTRIBUTING.md" '--user $(id -u):$(id -g)'
assert_file_contains "contribution guideline mandates the shared runtime-user helper" "$ROOT/CONTRIBUTING.md" "ensure_runtime_user"
assert_file_contains "contribution guideline forbids gosu escalation" "$ROOT/CONTRIBUTING.md" "no gosu"
assert_file_contains "contribution guideline mandates non-root image default" "$ROOT/CONTRIBUTING.md" 'USER ${USER_NAME}'

# Git + GitHub CLI contracts (coding agents lean on git and gh in every harness)
# git + gh moved into the shared base; the Node harnesses inherit them (their
# FROM ${BASE_IMAGE} is asserted below). The python cecli image is not on the
# shared base and still installs its own.
assert_file_contains "shared base installs git and gh for every Node harness" "$ROOT/defs/base/Dockerfile" "git gh"
assert_file_contains "cecli python image installs gh" "$ROOT/defs/cecli/Dockerfile.python" '    gh \'
assert_file_contains "shared wrapper lib forwards host git identity as env" "$ROOT/defs/lib/git-identity.sh" "proveo_git_identity_env_args()"
assert_file_contains "claudecode wrapper forwards host git identity" "$ROOT/defs/claudecode/run.sh" "proveo_git_identity_env_args"
assert_file_contains "opencode wrapper forwards host git identity" "$ROOT/defs/opencode/run.sh" "proveo_git_identity_env_args"
assert_file_contains "cursor wrapper forwards host git identity" "$ROOT/defs/cursor/run.sh" "proveo_git_identity_env_args"
assert_file_contains "cecli wrapper forwards host git identity" "$ROOT/defs/cecli/run.sh" "proveo_git_identity_env_args"
assert_file_contains "distributable CLI forwards host git identity" "$ROOT/apps/cli/public/cli/lib/runners.sh" "proveo_git_identity_env_args()"
assert_file_contains "entrypoint lib bridges env git identity into config-env" "$ROOT/packages/lib/entrypoint-lib.sh" "bridge_git_identity()"
assert_file_contains "git identity bridge uses git config-env, not files" "$ROOT/packages/lib/entrypoint-lib.sh" "GIT_CONFIG_COUNT"
assert_file_contains "cecli entrypoint attaches env-provided git identity" "$ROOT/defs/cecli/entrypoint.sh" "bridge_git_identity"
assert_file_contains "opencode entrypoint attaches env-provided git identity" "$ROOT/defs/opencode/entrypoint.sh" "bridge_git_identity"
assert_file_contains "cursor entrypoint attaches env-provided git identity" "$ROOT/defs/cursor/entrypoint.sh" "bridge_git_identity"
assert_file_contains "claudecode mcp entrypoint attaches env-provided git identity" "$ROOT/defs/claudecode/mcp/entrypoint.sh" "bridge_git_identity /workspace/input"
assert_file_contains "claudecode solo entrypoint attaches env-provided git identity" "$ROOT/defs/claudecode/solo/entrypoint.sh" "bridge_git_identity /workspace/input"
assert_file_contains "entrypoint lib reports git context at startup" "$ROOT/packages/lib/entrypoint-lib.sh" "report_git_context()"
assert_file_contains "git context report flags missing remote" "$ROOT/packages/lib/entrypoint-lib.sh" "Not tracking a remote repo"
assert_file_contains "git context report surfaces gh session state" "$ROOT/packages/lib/entrypoint-lib.sh" "gh auth status"
assert_file_contains "cecli entrypoint reports git context" "$ROOT/defs/cecli/entrypoint.sh" "report_git_context"
assert_file_contains "opencode entrypoint reports git context" "$ROOT/defs/opencode/entrypoint.sh" "report_git_context"
assert_file_contains "cursor entrypoint reports git context" "$ROOT/defs/cursor/entrypoint.sh" "report_git_context"
assert_file_contains "claudecode mcp entrypoint reports git context on the input mount" "$ROOT/defs/claudecode/mcp/entrypoint.sh" "report_git_context /workspace/input"
assert_file_contains "claudecode solo entrypoint reports git context on the input mount" "$ROOT/defs/claudecode/solo/entrypoint.sh" "report_git_context /workspace/input"

# Claude Code contracts
for variant_entrypoint in "$ROOT/defs/claudecode/mcp/entrypoint.sh" "$ROOT/defs/claudecode/solo/entrypoint.sh"; do
  assert_file_contains "claudecode variant entrypoint keeps dangerous full-consent launch" "$variant_entrypoint" "--dangerously-skip-permissions"
  assert_file_not_contains "claudecode variant entrypoint has no CLAUDE_DANGEROUS opt-out" "$variant_entrypoint" "CLAUDE_DANGEROUS"
  assert_file_contains "claudecode variant entrypoint seeds CLAUDE.md when missing" "$variant_entrypoint" "Seeded CLAUDE.md"
  assert_file_contains "claudecode variant entrypoint supports smoke mode" "$variant_entrypoint" "run_smoke_test"
done
assert_file_contains "shared entrypoint lib implements smoke mode" "$ROOT/packages/lib/entrypoint-lib.sh" "PROVEO_SMOKE_READY"
assert_file_contains "claudecode default prompt encodes verification loop" "$ROOT/defs/claudecode/defaults/CLAUDE.md" "Verification Commands"
assert_file_contains "claudecode run supports open egress mode" "$ROOT/defs/claudecode/run.sh" "open|proxy|firewall"
# Secure-by-default: every run wrapper starts in firewall mode; open is opt-in.
for runner_wrapper in claudecode cursor opencode cecli; do
  assert_file_contains "$runner_wrapper run defaults to firewall egress" "$ROOT/defs/$runner_wrapper/run.sh" 'EGRESS_MODE="firewall"'
done
# Distribution completeness: every buildable def — any defs dir with a
# build.sh — must be a registered mise build/deploy target with a working
# dir + image mapping, so a new def cannot silently miss Docker Hub. Derived
# from the filesystem, never a hand-maintained list.
for def_build in "$ROOT"/defs/*/build.sh "$ROOT"/defs/sidecars/*/build.sh; do
  [[ -f "$def_build" ]] || continue
  def_dir="$(dirname "$def_build")"
  def_name="$(basename "$def_dir")"
  # Resolve through the same source chain the mise tasks use, in a subshell so
  # the sourced CLI cannot clobber this test's helpers.
  resolved="$(REPO_ROOT="$ROOT" bash -s "$def_name" <<'INNER' 2>/dev/null
set -euo pipefail
source "$REPO_ROOT/apps/cli/public/cli/bin/proveo"
source "$REPO_ROOT/lib/helpers.sh"
source "$REPO_ROOT/lib/runners.sh"
name="$1"
registered=0
for t in "${TARGETS[@]}"; do
  [[ "$t" == "$name" ]] && registered=1
done
[[ "$registered" == 1 ]] || { echo "unregistered"; exit 0; }
printf '%s|%s\n' "$(target_dir "$name")" "$(image_name "$name")"
INNER
)"
  if [[ "$resolved" == "$def_dir|proveo/"* ]]; then
    pass "buildable def '$def_name' is a mise target with dir + image mappings"
  else
    fail "buildable def '$def_name' is a mise target with dir + image mappings" \
      "Expected TARGETS (lib/runners.sh) to include '$def_name' resolving to '$def_dir|proveo/…', got: ${resolved:-nothing}"
  fi
done
assert_file_contains "mise test suite covers the cursor def" "$ROOT/mise.toml" 'defs/cursor/test.sh'

# Shared-base structure: every Node-based harness builds FROM proveo/base (one
# common layer set across images) and re-runs the baked hardening pass after
# installing its extras. The Solidity toolchain lives only in the sol variant.
for harness_dockerfile in \
  defs/claudecode/mcp/Dockerfile defs/claudecode/solo/Dockerfile \
  defs/cursor/Dockerfile defs/opencode/Dockerfile defs/cecli/Dockerfile.node; do
  assert_file_contains "$harness_dockerfile builds FROM the shared base" "$ROOT/$harness_dockerfile" 'FROM ${BASE_IMAGE}'
  assert_file_contains "$harness_dockerfile re-runs the baked harden pass" "$ROOT/$harness_dockerfile" 'proveo-harden'
done
assert_file_contains "base image bakes the harden pass" "$ROOT/defs/base/Dockerfile" "proveo-harden"
assert_file_contains "sol variant carries Foundry" "$ROOT/defs/claudecode/sol/Dockerfile" "foundryup"
assert_file_contains "sol variant carries semgrep" "$ROOT/defs/claudecode/sol/Dockerfile" "semgrep"
assert_file_not_contains "claudecode mcp variant sheds Foundry" "$ROOT/defs/claudecode/mcp/Dockerfile" "foundryup"
assert_file_not_contains "claudecode solo variant sheds Foundry" "$ROOT/defs/claudecode/solo/Dockerfile" "foundryup"
assert_file_not_contains "claudecode mcp variant sheds solc" "$ROOT/defs/claudecode/mcp/Dockerfile" "solc-select"
assert_file_contains "claudecode manifest registers the sol variant" "$ROOT/defs/claudecode/harness.manifest" "proveo/claudecode-sol"

# Consumer CLI target surface: cursor and claudecode-sol are runnable targets.
assert_file_contains "consumer CLI lists the cursor target" "$ROOT/apps/cli/public/cli/bin/proveo" '"cursor"'
assert_file_contains "consumer CLI dispatches cursor runs" "$ROOT/apps/cli/public/cli/lib/runners.sh" 'run_cursor'
assert_file_contains "consumer cursor runner forwards the API key by name only" "$ROOT/apps/cli/public/cli/lib/runners.sh" '(-e CURSOR_API_KEY)'
assert_file_contains "consumer CLI dispatches claudecode-sol runs" "$ROOT/apps/cli/public/cli/lib/runners.sh" 'claudecode|claudecode-solo|claudecode-sol)'
assert_file_contains "claudecode parent runner sources shared egress lifecycle" "$ROOT/defs/claudecode/run.sh" 'source "$DEFS_DIR/lib/egress.sh"'
assert_file_contains "claudecode parent runner owns debug shell flow" "$ROOT/defs/claudecode/run.sh" '--shell'
assert_file_contains "claudecode parent runner selects mcp variant image" "$ROOT/defs/claudecode/run.sh" 'PROVEO_CLAUDECODE_IMAGE'
assert_file_contains "claudecode parent runner selects solo variant image" "$ROOT/defs/claudecode/run.sh" 'PROVEO_CLAUDECODE_SOLO_IMAGE'

# OpenCode contracts
assert_file_contains "opencode entrypoint seeds project AGENTS.md" "$ROOT/defs/opencode/entrypoint.sh" "Seeded AGENTS.md"
assert_file_contains "opencode reseeds project AGENTS.md with OPENCODE_RESEED" "$ROOT/defs/opencode/entrypoint.sh" "Re-seeded AGENTS.md"
assert_file_contains "opencode entrypoint reports team workflow" "$ROOT/defs/opencode/entrypoint.sh" "Lead flow: classify"
assert_file_contains "opencode entrypoint applies shared model bridges" "$ROOT/defs/opencode/entrypoint.sh" "apply_env_bridges"
assert_file_contains "shared bridges map ARCHITECT_MODEL to opencode" "$ROOT/packages/lib/entrypoint-lib.sh" '"from": "ARCHITECT_MODEL", "to": "OPENCODE_MODEL"'
assert_file_contains "shared bridges map EDITOR_MODEL to opencode" "$ROOT/packages/lib/entrypoint-lib.sh" '"from": "EDITOR_MODEL", "to": "OPENCODE_BUILD_MODEL"'
assert_file_contains "opencode supports smoke mode" "$ROOT/defs/opencode/entrypoint.sh" "PROVEO_SMOKE_READY"
assert_file_contains "opencode team prompt defines review gates" "$ROOT/defs/opencode/defaults/AGENTS.md" "Review Gates"
assert_file_contains "opencode team prompt defines routing matrix" "$ROOT/defs/opencode/defaults/AGENTS.md" "Routing Matrix"
assert_file_contains "opencode config keeps plan read-only" "$ROOT/defs/opencode/defaults/opencode.json" '"edit": "deny"'
assert_file_contains "opencode config keeps build bash ask" "$ROOT/defs/opencode/defaults/opencode.json" '"bash": "ask"'
assert_file_contains "opencode image bakes shared verification lib" "$ROOT/defs/opencode/Dockerfile" "COPY defs/lib/ /opt/proveo/lib/"
assert_file_contains "opencode build uses repo-root context" "$ROOT/defs/opencode/build.sh" '"$SCRIPT_DIR/../.."'

# Cursor contracts (policy-gated autonomous loop)
assert_file_contains "cursor entrypoint keeps policy-gated full-consent launch" "$ROOT/defs/cursor/entrypoint.sh" "agent \"\${LAUNCH_ARGS[@]}\""
assert_file_contains "cursor entrypoint launches with --force autonomy" "$ROOT/defs/cursor/entrypoint.sh" "LAUNCH_ARGS=(--force --sandbox disabled)"
assert_file_contains "cursor entrypoint supports smoke mode" "$ROOT/defs/cursor/entrypoint.sh" "run_smoke_test"
assert_file_contains "cursor entrypoint reseeds home config on demand" "$ROOT/defs/cursor/entrypoint.sh" "CURSOR_RESEED"
assert_file_contains "cursor entrypoint keeps workspace seeding opt-in" "$ROOT/defs/cursor/entrypoint.sh" "CURSOR_SEED_RULES"
assert_file_not_contains "cursor entrypoint never seeds the workspace unconditionally" "$ROOT/defs/cursor/entrypoint.sh" "Seeded AGENTS.md"
assert_file_contains "cursor deny baseline survives --force (privilege escalation)" "$ROOT/defs/cursor/defaults/cli-config.json" '"Shell(sudo)"'
assert_file_contains "cursor deny baseline protects credential material" "$ROOT/defs/cursor/defaults/cli-config.json" '"Read(.env*)"'
assert_file_contains "cursor image bakes the root-owned enterprise hook layer" "$ROOT/defs/cursor/Dockerfile" "/etc/cursor/hooks.json"
assert_file_contains "cursor enterprise hooks wire the shell audit" "$ROOT/defs/cursor/defaults/hooks.json" "beforeShellExecution"
assert_file_contains "cursor audit hook is fail-open by design" "$ROOT/defs/cursor/defaults/hooks/audit-shell.sh" '{"permission":"allow"}'
assert_executable "cursor audit hook is executable" "$ROOT/defs/cursor/defaults/hooks/audit-shell.sh"
assert_file_contains "cursor reviewer subagents are structurally readonly" "$ROOT/defs/cursor/defaults/agents/adversarial-reviewer.md" "readonly: true"
assert_file_contains "cursor loop rule encodes the verification loop" "$ROOT/defs/cursor/defaults/rules/proveo-loop.mdc" "Verification Commands"
assert_file_contains "cursor run wrapper sources shared egress lifecycle" "$ROOT/defs/cursor/run.sh" 'source "$DEFS_DIR/lib/egress.sh"'
assert_file_contains "cursor run supports the three egress modes" "$ROOT/defs/cursor/run.sh" "open|proxy|firewall"
assert_file_contains "cursor run rejects local models (vendor-pinned inference)" "$ROOT/defs/cursor/run.sh" "no local-model path"
assert_file_not_contains "cursor run has no --local-model flag" "$ROOT/defs/cursor/run.sh" '--local-model)'
assert_file_contains "cursor entrypoint handles proxied HTTP/2 fallback" "$ROOT/defs/cursor/entrypoint.sh" "useHttp1ForAgent"
# Provider knowledge was retired from egress.sh into the Go registry (single
# source). Assert it there.
assert_file_contains "provider registry pins the Cursor backend for CURSOR_API_KEY" "$ROOT/internal/provider/provider.go" ".cursor.sh .cursor.com"
assert_file_contains "provider registry detects the cursor provider" "$ROOT/internal/provider/provider.go" "CURSOR_API_KEY"
assert_file_contains "cursor image bakes shared verification lib" "$ROOT/defs/cursor/Dockerfile" "COPY defs/lib/ /opt/proveo/lib/"
assert_file_contains "cursor build uses repo-root context" "$ROOT/defs/cursor/build.sh" '"$SCRIPT_DIR/../.."'

# Cecli contracts
assert_file_contains "cecli entrypoint seeds CONVENTIONS.md" "$ROOT/defs/cecli/entrypoint.sh" "Seeded CONVENTIONS.md"
assert_file_contains "cecli entrypoint bridges ARCHITECT_MODEL" "$ROOT/defs/cecli/entrypoint.sh" "ARCHITECT_MODEL"
assert_file_contains "cecli entrypoint bridges EDITOR_MODEL" "$ROOT/defs/cecli/entrypoint.sh" "EDITOR_MODEL"
assert_file_contains "cecli entrypoint bridges SMALL_MODEL" "$ROOT/defs/cecli/entrypoint.sh" "SMALL_MODEL"
assert_file_contains "cecli supports smoke mode" "$ROOT/defs/cecli/entrypoint.sh" "run_smoke_test"
assert_file_contains "cecli runtime caps subagents" "$ROOT/defs/cecli/entrypoint.sh" "max_sub_agents"
assert_file_contains "cecli sample keeps auto-commits enabled" "$ROOT/defs/cecli/sample.cecli.conf.yml" "auto-commits: true"
assert_file_contains "cecli sample keeps auto-load disabled" "$ROOT/defs/cecli/sample.cecli.conf.yml" "auto-load: false"
assert_file_contains "cecli sample keeps compaction enabled" "$ROOT/defs/cecli/sample.cecli.conf.yml" "enable-context-compaction: true"
assert_file_contains "cecli conventions keep pair-programming containment" "$ROOT/defs/cecli/defaults/CONVENTIONS.md" "Do not autonomously explore the entire repository"
assert_file_not_contains "cecli conventions do not forbid auto-commit" "$ROOT/defs/cecli/defaults/CONVENTIONS.md" "Never auto-commit"
assert_file_contains "cecli node image bakes local verification lib" "$ROOT/defs/cecli/Dockerfile.node" "COPY defs/cecli/proveo-lib/ /opt/proveo/lib/"
assert_file_contains "cecli python image bakes local verification lib" "$ROOT/defs/cecli/Dockerfile.python" "COPY defs/cecli/proveo-lib/ /opt/proveo/lib/"
assert_file_contains "cecli local verification lib contains detector" "$ROOT/defs/cecli/proveo-lib/detect-verify.sh" "detect_verify_commands()"
assert_file_contains "cecli build uses repo-root context" "$ROOT/defs/cecli/build.sh" '"$SCRIPT_DIR/../.."'

# Build context contracts for Claude variants
assert_file_contains "claudecode mcp image bakes local verification lib" "$ROOT/defs/claudecode/mcp/Dockerfile" "COPY --chown=\${USER_NAME}:\${USER_NAME} defs/claudecode/mcp/proveo-lib/ /opt/proveo/lib/"
assert_file_contains "claudecode solo image bakes local verification lib" "$ROOT/defs/claudecode/solo/Dockerfile" "COPY --chown=\${USER_NAME}:\${USER_NAME} defs/claudecode/solo/proveo-lib/ /opt/proveo/lib/"
assert_file_contains "claudecode mcp local verification lib contains detector" "$ROOT/defs/claudecode/mcp/proveo-lib/detect-verify.sh" "detect_verify_commands()"
assert_file_contains "claudecode solo local verification lib contains detector" "$ROOT/defs/claudecode/solo/proveo-lib/detect-verify.sh" "detect_verify_commands()"
assert_file_contains "claudecode build uses variant-local Dockerfile with repo-root context" "$ROOT/defs/claudecode/build.sh" '-f "$SCRIPT_DIR/$variant/Dockerfile" "$SCRIPT_DIR/../.."'

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
assert_file_contains "egress preflight pulls published images, guides a local build on pull failure" "$ROOT/defs/lib/egress.sh" "image not built"
assert_file_contains "egress prepare fails fast when an image is not ready" "$ROOT/defs/lib/egress.sh" "egress preflight failed"
assert_file_contains "egress sidecar start checks the docker run exit code" "$ROOT/defs/lib/egress.sh" "failed to start Squid sidecar"
assert_file_contains "egress tests reuse the shared image preflight (dedupe)" "$ROOT/defs/claudecode/tests/test_egress.sh" "proveo_egress_ensure_image"

# Provider allowlist (pin model-provider egress; auto-detected from API keys)
assert_file_contains "squid.conf includes the provider allowlist" "$ROOT/defs/sidecars/squid-proxy/squid.conf" "include /etc/squid/provider-allow.conf"
assert_file_contains "egress auto-detects the provider from the present API key" "$ROOT/defs/lib/egress.sh" "proveo_egress_detect_providers"
# The provider map + Squid write-pin ACL were retired from egress.sh into Go
# (internal/provider = endpoints, internal/egress = allowlist rendering).
assert_file_contains "provider registry maps trusted first-party APIs (anthropic)" "$ROOT/internal/provider/provider.go" ".anthropic.com"
assert_file_contains "provider registry maps GMI Cloud inference endpoint" "$ROOT/internal/provider/provider.go" ".gmi-serving.com"
assert_file_contains "provider registry scopes hyperscaler endpoints tightly (bedrock regex)" "$ROOT/internal/provider/provider.go" "bedrock-runtime"
assert_file_contains "provider pin governs writes, not reads (no deny-all)" "$ROOT/internal/egress/egress.go" "http_access allow unsafe_methods provider_allow"
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
