#!/usr/bin/env bash
# tests/test_egress.sh - Egress mode contract tests.

if [[ -z "${PROJECT_ROOT:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  # shellcheck source=helpers.sh
  source "$SCRIPT_DIR/helpers.sh"
fi

egress_pass() {
  local desc="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} [%d] %s\n" "$TESTS_RUN" "$desc"
}

egress_fail() {
  local desc="$1" detail="${2:-}"
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("$desc")
  printf "${RED}FAIL${NC} [%d] %s\n" "$TESTS_RUN" "$desc"
  [[ -n "$detail" ]] && printf "     %s\n" "$detail"
}

assert_file_contains() {
  local desc="$1" file="$2" expected="$3"
  if grep -qF -- "$expected" "$file"; then
    egress_pass "$desc"
  else
    egress_fail "$desc" "Expected '$expected' in $file"
  fi
}

assert_file_not_contains() {
  local desc="$1" file="$2" unexpected="$3"
  if grep -qF -- "$unexpected" "$file"; then
    egress_fail "$desc" "Did not expect '$unexpected' in $file"
  else
    egress_pass "$desc"
  fi
}

run_with_fake_docker() {
  local mode="$1" capture_dir="$2" output_file="$3" local_model="${4:-}"
  local fakebin="$capture_dir/bin"
  mkdir -p "$fakebin"
  cat >"$fakebin/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker ' >>"${PROVEO_FAKE_DOCKER_ARGS:?}"
printf '%q ' "$@" >>"${PROVEO_FAKE_DOCKER_ARGS:?}"
printf '\n' >>"${PROVEO_FAKE_DOCKER_ARGS:?}"
EOF
  chmod +x "$fakebin/docker"

  : >"$capture_dir/docker.args"
  # run.sh keeps egress artifacts (logs + mitmproxy CA) out of the agent's mounts
  # under PROVEO_EGRESS_ROOT; point it at a scratch dir separate from --output-dir
  # so this test also proves the audit dir is not the agent's writable output.
  local egress_root="$capture_dir/state"
  if [[ "$mode" == "firewall" ]]; then
    # Pre-seed the mitmproxy CA so the CA-wait returns instantly under fake
    # docker (no real container generates it). Mirrors mitmproxy's own output.
    local mitm_confdir="$egress_root/egress/test-${mode}/mitmproxy/confdir"
    mkdir -p "$mitm_confdir"
    printf -- '-----BEGIN CERTIFICATE-----\n' >"$mitm_confdir/mitmproxy-ca-cert.pem"
  fi
  PROVEO_FAKE_DOCKER_ARGS="$capture_dir/docker.args" \
  PATH="$fakebin:$PATH" \
  CLAUDE_CODE_OAUTH_TOKEN="test-token" \
  PROVEO_EGRESS_SESSION="test-${mode}" \
  PROVEO_EGRESS_ROOT="$egress_root" \
  PROVEO_MITM_CA_WAIT_SECS="3" \
  PROVEO_LOCAL_MODEL="$local_model" \
  "$PROJECT_ROOT/run.sh" --variant solo --egress-mode "$mode" --output-dir "$capture_dir/reports" -- --version >"$output_file" 2>&1
}

# Level-2 contract: assigning a local model attaches an Ollama sidecar to the
# agent network and wires the model env, while keeping it off the egress proxy.
assert_local_model_contract() {
  local mode="$1"
  local tmp output args
  tmp="$(mktemp -d)"
  output="$tmp/output.txt"
  args="$tmp/docker.args"

  if ! run_with_fake_docker "$mode" "$tmp" "$output" "gemma4"; then
    egress_fail "[$mode+local] wrapper launches with fake docker" "$(tr '\n' ' ' <"$output")"
    rm -rf "$tmp"
    return
  fi

  assert_file_contains "[$mode+local] starts ollama sidecar with alias" "$args" "--network-alias ollama"
  assert_file_contains "[$mode+local] binds ollama on all interfaces" "$args" "OLLAMA_HOST=0.0.0.0:11434"
  assert_file_contains "[$mode+local] serves host models read-only" "$args" ":/models:ro"
  assert_file_contains "[$mode+local] sets ollama models dir" "$args" "OLLAMA_MODELS=/models"
  assert_file_contains "[$mode+local] points harness model env at ollama" "$args" "OLLAMA_API_BASE=http://ollama:11434"
  assert_file_contains "[$mode+local] exposes OpenAI-compatible base url" "$args" "OPENAI_BASE_URL=http://ollama:11434/v1"
  assert_file_contains "[$mode+local] assigns gemma4 via the model bridge" "$args" "ARCHITECT_MODEL=ollama/gemma4"
  # Match a comma-free prefix: bash's %q in the fake-docker recorder escapes
  # commas, so assert the meaningful part (ollama is in the no-proxy list).
  assert_file_contains "[$mode+local] local model bypasses the egress proxy" "$args" "NO_PROXY=ollama"
  assert_file_contains "[$mode+local] reports the assigned local model" "$output" "Local model: ollama/gemma4"
  rm -rf "$tmp"
}

# No-Docker: feed a synthetic Squid access.log to the post-run reporter and
# check it ranks the top allowed (external) and top denied operations, and
# excludes host-local destinations.
assert_egress_report_ranking() {
  local tmp dir r
  tmp="$(mktemp -d)"
  dir="$tmp/egress/sess"
  r="$dir/report.txt"
  mkdir -p "$dir/squid/logs"
  cat >"$dir/squid/logs/access.log" <<'LOG'
1700000000.001 10 172.20.0.3 TCP_TUNNEL/200 100 CONNECT api.anthropic.com:443 - HIER_DIRECT/1.2.3.4 -
1700000000.002 10 172.20.0.3 TCP_TUNNEL/200 100 CONNECT api.anthropic.com:443 - HIER_DIRECT/1.2.3.4 -
1700000000.003 10 172.20.0.3 TCP_TUNNEL/200 100 CONNECT api.anthropic.com:443 - HIER_DIRECT/1.2.3.4 -
1700000000.004 10 172.20.0.3 TCP_MISS/200 100 GET http://docs.example.com/guide - HIER_DIRECT/5.6.7.8 text/html
1700000000.005 10 172.20.0.3 TCP_MISS/200 100 GET http://docs.example.com/api - HIER_DIRECT/5.6.7.8 text/html
1700000000.006 0 172.20.0.3 TCP_DENIED/403 0 GET http://169.254.169.254/latest/meta-data/ - HIER_NONE/- text/html
1700000000.007 0 172.20.0.3 TCP_DENIED/403 0 GET http://169.254.169.254/latest/meta-data/ - HIER_NONE/- text/html
1700000000.008 0 172.20.0.3 TCP_DENIED/403 0 GET http://169.254.169.254/latest/meta-data/ - HIER_NONE/- text/html
1700000000.009 0 172.20.0.3 TCP_DENIED/403 0 GET http://10.255.255.1/ - HIER_NONE/- text/html
1700000000.010 0 172.20.0.3 TCP_DENIED/403 0 POST http://example.com/ - HIER_NONE/- text/html
1700000000.011 5 172.20.0.3 TCP_TUNNEL/200 50 CONNECT ollama:11434 - HIER_DIRECT/172.20.0.9 -
LOG
  (
    # shellcheck source=../../lib/egress.sh
    source "$PROJECT_ROOT/../lib/egress.sh"
    PROVEO_EGRESS_DIR="$dir"
    PROVEO_EGRESS_SESSION_ID="sess"
    PROVEO_EGRESS_MODE="proxy"
    proveo_egress_report >/dev/null 2>&1
  )
  assert_file_contains "[report] generates a report file" "$r" "Top 5 ALLOWED"
  assert_file_contains "[report] top allowed external op ranked first (3x)" "$r" "3 CONNECT api.anthropic.com:443"
  assert_file_contains "[report] second allowed external op present (2x)" "$r" "2 GET docs.example.com"
  assert_file_contains "[report] top denied op ranked first (3x)" "$r" "3 GET 169.254.169.254"
  assert_file_contains "[report] denied includes blocked private range" "$r" "GET 10.255.255.1"
  assert_file_not_contains "[report] host-local ollama excluded from report" "$r" "ollama:11434"
  assert_file_contains "[report] machine-readable json is written" "$dir/report.json" "\"top_denied\""
  rm -rf "$tmp"
}

# No-Docker: provider allowlist generation + key-based auto-detection.
# Generates provider-allow.conf in a subshell with controlled env and asserts.
assert_provider_allowlist_contracts() {
  local tmp f lib; tmp="$(mktemp -d)"; f="$tmp/provider-allow.conf"
  lib="$PROJECT_ROOT/../lib/egress.sh"

  # Detection: the present API key IS the provider intent (no flag).
  local d
  d="$(unset PROVEO_EGRESS_PROVIDER; ANTHROPIC_API_KEY=sk-x bash -c "source '$lib'; proveo_egress_detect_providers")"
  [[ "$d" == *anthropic* ]] && egress_pass "[provider] ANTHROPIC_API_KEY auto-detects anthropic" || egress_fail "[provider] ANTHROPIC_API_KEY auto-detects anthropic" "got: $d"
  d="$(unset PROVEO_EGRESS_PROVIDER ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN; AWS_ACCESS_KEY_ID=AKIA bash -c "source '$lib'; proveo_egress_detect_providers")"
  [[ "$d" == *bedrock* ]] && egress_pass "[provider] AWS key auto-detects bedrock" || egress_fail "[provider] AWS key auto-detects bedrock" "got: $d"
  d="$(unset PROVEO_EGRESS_PROVIDER ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN; GMI_API_KEY=gmi bash -c "source '$lib'; proveo_egress_detect_providers")"
  [[ "$d" == *gmi* ]] && egress_pass "[provider] GMI_API_KEY auto-detects gmi" || egress_fail "[provider] GMI_API_KEY auto-detects gmi" "got: $d"

  # Generation: explicit provider → write-allow + reads preserved (no deny-all).
  ( unset ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN; PROVEO_EGRESS_PROVIDER=together bash -c "source '$lib'; proveo_egress_write_provider_allow '$f'" ) >/dev/null 2>&1
  assert_file_contains "[provider] together pins inference writes to its endpoint" "$f" "acl provider_allow dstdomain .together.xyz"
  assert_file_contains "[provider] write-pin allows unsafe methods to provider only" "$f" "http_access allow unsafe_methods provider_allow"
  assert_file_not_contains "[provider] reads stay open — no deny-all (scraping preserved)" "$f" "http_access deny all"

  # Generation: GMI Cloud endpoint.
  ( PROVEO_EGRESS_PROVIDER=gmi bash -c "source '$lib'; proveo_egress_write_provider_allow '$f'" ) >/dev/null 2>&1
  assert_file_contains "[provider] gmi pins to api.gmi-serving.com" "$f" ".gmi-serving.com"

  # Generation: hyperscaler is scoped tightly (only the inference host).
  ( PROVEO_EGRESS_PROVIDER=bedrock bash -c "source '$lib'; proveo_egress_write_provider_allow '$f'" ) >/dev/null 2>&1
  assert_file_contains "[provider] bedrock scoped to bedrock-runtime, not all of AWS" "$f" "bedrock-runtime"
  assert_file_not_contains "[provider] bedrock does not allow all of .amazonaws.com" "$f" "dstdomain .amazonaws.com"

  # Generation: auto-detect (no explicit provider) drives the allowlist.
  ( unset PROVEO_EGRESS_PROVIDER ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN; OPENAI_API_KEY=sk bash -c "source '$lib'; proveo_egress_write_provider_allow '$f'" ) >/dev/null 2>&1
  assert_file_contains "[provider] auto-detected openai key pins openai endpoint" "$f" ".openai.com"

  # Generation: nothing pinned/detected → no-op (base read-allow/write-deny).
  ( unset PROVEO_EGRESS_PROVIDER ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN OPENAI_API_KEY AWS_ACCESS_KEY_ID GMI_API_KEY; bash -c "source '$lib'; proveo_egress_write_provider_allow '$f'" ) >/dev/null 2>&1
  assert_file_not_contains "[provider] no provider/key → no allowlist rule" "$f" "acl provider_allow"

  rm -rf "$tmp"
}

# Live: prove the provider write-pin while reads stay open. Uses the Squid access
# log as the allow/deny oracle (origin 4xx must not be confused with a proxy
# denial). Synthetic provider = example.com via the custom-domains override.
run_provider_allowlist_integration() {
  local tmp; tmp="$(mktemp -d)"
  unset PROVEO_EGRESS_SESSION_ID PROVEO_EGRESS_DIR
  PROVEO_EGRESS_SESSION="integration-provider-$$"
  PROVEO_EGRESS_PROVIDER="custom"
  PROVEO_EGRESS_PROVIDER_DOMAINS=".example.com"
  if proveo_egress_prepare proxy integration "$tmp/reports"; then
    local log="$PROVEO_EGRESS_DIR/squid/logs/access.log"
    # Make the four attempts (exit codes irrelevant; the log is the oracle).
    docker run --rm "${PROVEO_EGRESS_AGENT_DOCKER_ARGS[@]}" "$CURL_IMAGE" -s -o /dev/null --max-time 20 --retry 20 --retry-connrefused --retry-delay 2 http://example.com/ >/dev/null 2>&1 || true
    docker run --rm "${PROVEO_EGRESS_AGENT_DOCKER_ARGS[@]}" "$CURL_IMAGE" -s -o /dev/null --max-time 15 http://neverssl.com/ >/dev/null 2>&1 || true
    docker run --rm "${PROVEO_EGRESS_AGENT_DOCKER_ARGS[@]}" "$CURL_IMAGE" -s -o /dev/null --max-time 15 -X POST http://example.com/ >/dev/null 2>&1 || true
    docker run --rm "${PROVEO_EGRESS_AGENT_DOCKER_ARGS[@]}" "$CURL_IMAGE" -s -o /dev/null --max-time 15 -X POST http://neverssl.com/ >/dev/null 2>&1 || true
    local waited=0
    until grep -qF "POST http://neverssl.com" "$log" 2>/dev/null || (( waited >= 10 )); do sleep 1; waited=$((waited + 1)); done

    _log_denied() { grep -F "$1" "$log" 2>/dev/null | tail -1 | grep -q "TCP_DENIED"; }
    # Reads to ANY host stay allowed — scraping/docs/search must keep working.
    if _log_denied "GET http://neverssl.com"; then
      egress_fail "[integration/provider] web reads stay open (scraping not blocked)" "neverssl GET was denied"
    else
      egress_pass "[integration/provider] web reads stay open (scraping not blocked)"
    fi
    if _log_denied "GET http://example.com"; then
      egress_fail "[integration/provider] read to provider host allowed"
    else
      egress_pass "[integration/provider] read to provider host allowed"
    fi
    # Inference writes pinned to the provider; writes elsewhere denied.
    if _log_denied "POST http://example.com"; then
      egress_fail "[integration/provider] inference write to provider allowed" "provider POST was denied"
    else
      egress_pass "[integration/provider] inference write to provider allowed"
    fi
    if _log_denied "POST http://neverssl.com"; then
      egress_pass "[integration/provider] write to non-provider host denied"
    else
      egress_fail "[integration/provider] write to non-provider host denied" "non-provider POST was not denied"
    fi
  else
    egress_fail "[integration/provider] prepare egress topology"
  fi
  unset PROVEO_EGRESS_PROVIDER PROVEO_EGRESS_PROVIDER_DOMAINS
  proveo_egress_cleanup
  rm -rf "$tmp"
}

# --- Level-3 live egress helpers: exercise the prepared agent Docker args ---
# Both rely on globals set by run_live_egress_integration: CURL_IMAGE and the
# PROVEO_EGRESS_AGENT_DOCKER_ARGS populated by proveo_egress_prepare.
assert_egress_allowed() {
  local desc="$1"; shift
  TESTS_RUN=$((TESTS_RUN + 1))
  if docker run --rm "${PROVEO_EGRESS_AGENT_DOCKER_ARGS[@]}" "$CURL_IMAGE" "$@" >/dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${NC} [%d] %s\n" "$TESTS_RUN" "$desc"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES+=("$desc")
    printf "${RED}FAIL${NC} [%d] %s (egress unexpectedly denied)\n" "$TESTS_RUN" "$desc"
  fi
}

assert_egress_blocked() {
  local desc="$1"; shift
  TESTS_RUN=$((TESTS_RUN + 1))
  if docker run --rm "${PROVEO_EGRESS_AGENT_DOCKER_ARGS[@]}" "$CURL_IMAGE" "$@" >/dev/null 2>&1; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES+=("$desc")
    printf "${RED}FAIL${NC} [%d] %s (egress unexpectedly allowed)\n" "$TESTS_RUN" "$desc"
  else
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${NC} [%d] %s\n" "$TESTS_RUN" "$desc"
  fi
}

# Gated local-model integration: proves the assigned Ollama model is reachable
# on the agent network while the egress layer still blocks bad destinations.
run_local_model_integration() {
  local model="${PROVEO_EGRESS_LOCAL_MODEL:-gemma4}"
  local ollama_image="${PROVEO_OLLAMA_IMAGE:-ollama/ollama:latest}"
  if ! ensure_docker_image "$ollama_image"; then
    skip_test "egress integration: local model sidecar" "missing $ollama_image; set PROVEO_EGRESS_PULL=1 to pull"
    return 0
  fi
  local tmp
  tmp="$(mktemp -d)"
  unset PROVEO_EGRESS_SESSION_ID PROVEO_EGRESS_DIR
  PROVEO_EGRESS_SESSION="integration-local-$$"
  PROVEO_LOCAL_MODEL="$model"
  if proveo_egress_prepare proxy integration "$tmp/reports"; then
    assert_egress_allowed "[integration/local] assigned model endpoint (ollama:11434) is reachable" \
      -fsS --retry 10 --retry-connrefused --retry-delay 2 --max-time 60 http://ollama:11434/api/tags
    assert_egress_blocked "[integration/local] egress still blocks metadata SSRF with local model active" \
      -fsS --max-time 10 http://169.254.169.254/
  else
    egress_fail "[integration/local] prepare egress topology"
  fi
  unset PROVEO_LOCAL_MODEL
  proveo_egress_cleanup
  rm -rf "$tmp"
}

assert_mode_contract() {
  local mode="$1"
  local tmp output args
  tmp="$(mktemp -d)"
  output="$tmp/output.txt"
  args="$tmp/docker.args"

  if ! run_with_fake_docker "$mode" "$tmp" "$output"; then
    egress_fail "[$mode] wrapper launches with fake docker" "$(tr '\n' ' ' <"$output")"
    rm -rf "$tmp"
    return
  fi

  case "$mode" in
    broker)
      assert_file_not_contains "[broker] allows arbitrary mock protocol egress by installing no proxy" "$args" "HTTP_PROXY="
      assert_file_not_contains "[broker] has no Squid enforcement proxy" "$args" "ENFORCEMENT_PROXY="
      assert_file_not_contains "[broker] has no mitmproxy inspection proxy" "$args" "INSPECT_PROXY="
      assert_file_contains "[broker] keeps the default bridge network contract" "$args" "--network=bridge"
      assert_file_not_contains "[broker] starts no sidecar networks" "$args" "network create"
      ;;
    proxy)
      assert_file_contains "[proxy] creates an internal agent-to-Squid network" "$args" "network create --label proveo.egress.session=test-proxy --internal test-proxy-claudecode-solo-squid-net"
      assert_file_contains "[proxy] creates Squid egress network" "$args" "network create --label proveo.egress.session=test-proxy test-proxy-squid-egress-net"
      assert_file_contains "[proxy] starts Squid sidecar" "$args" "--name test-proxy-squid"
      assert_file_contains "[proxy] starts Squid on internet-capable egress network" "$args" "--network test-proxy-squid-egress-net"
      assert_file_contains "[proxy] connects Squid back to internal network with alias" "$args" "network connect --alias squid test-proxy-claudecode-solo-squid-net test-proxy-squid"
      assert_file_contains "[proxy] blocks non-web protocols through Squid enforcement" "$args" "ENFORCEMENT_PROXY=http://squid:3128"
      assert_file_contains "[proxy] routes HTTP through Squid" "$args" "HTTP_PROXY=http://squid:3128"
      assert_file_contains "[proxy] routes HTTPS through Squid" "$args" "HTTPS_PROXY=http://squid:3128"
      assert_file_not_contains "[proxy] does not route through mitmproxy inspector" "$args" "INSPECT_PROXY="
      assert_file_not_contains "[proxy] agent is not attached to default bridge" "$args" "--network=bridge"
      ;;
    firewall)
      assert_file_contains "[firewall] creates agent-to-mitmproxy internal network" "$args" "network create --label proveo.egress.session=test-firewall --internal test-firewall-claudecode-solo-mitm-net"
      assert_file_contains "[firewall] creates mitmproxy-to-Squid internal network" "$args" "network create --label proveo.egress.session=test-firewall --internal test-firewall-mitm-squid-net"
      assert_file_contains "[firewall] starts Squid sidecar" "$args" "--name test-firewall-squid"
      assert_file_contains "[firewall] starts Squid on internet-capable egress network" "$args" "--network test-firewall-squid-egress-net"
      assert_file_contains "[firewall] connects Squid back to mitmproxy network with alias" "$args" "network connect --alias squid test-firewall-mitm-squid-net test-firewall-squid"
      assert_file_contains "[firewall] starts inspector first-hop alias" "$args" "--network-alias mitm"
      assert_file_contains "[firewall] points the inspector at Squid upstream" "$args" "PROVEO_EGRESS_UPSTREAM=http://squid:3128"
      assert_file_contains "[firewall] mounts inspector confdir for CA generation" "$args" "/mitmproxy/confdir:/confdir"
      assert_file_contains "[firewall] mounts inspector flows for analytics" "$args" "/mitmproxy/flows:/flows"
      assert_file_contains "[firewall] connects the inspector to the Squid network" "$args" "network connect test-firewall-mitm-squid-net test-firewall-egress"
      assert_file_contains "[firewall] blocks non-web protocols through Squid enforcement" "$args" "ENFORCEMENT_PROXY=http://squid:3128"
      assert_file_contains "[firewall] routes first hop through mitmproxy for capture" "$args" "HTTP_PROXY=http://mitm:8888"
      assert_file_contains "[firewall] exposes mitmproxy inspection proxy" "$args" "INSPECT_PROXY=http://mitm:8888"
      assert_file_contains "[firewall] trusts the mitmproxy CA in the agent" "$args" "NODE_EXTRA_CA_CERTS=/etc/proveo/mitmproxy-ca-cert.pem"
      assert_file_contains "[firewall] records egress log directory" "$output" "Egress logs:"
      assert_file_not_contains "[firewall] agent is not attached to default bridge" "$args" "--network=bridge"
      ;;
  esac

  rm -rf "$tmp"
}

docker_ready() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

# Skip-friendly gate over the shared egress image preflight (defined in
# egress.sh, sourced by run_live_egress_integration before this is called):
# present images are ready; missing pullable images are only fetched when
# PROVEO_EGRESS_PULL=1 so CI never triggers large pulls; proveo/* must be built.
ensure_docker_image() {
  local image="$1"
  proveo_egress_image_present "$image" && return 0
  [[ "${PROVEO_EGRESS_PULL:-0}" =~ ^(1|true|yes|on)$ ]] || return 1
  proveo_egress_ensure_image "$image"
}

run_live_egress_integration() {
  if ! docker_ready; then
    skip_test "egress integration: Docker daemon" "Docker is unavailable"
    return 0
  fi

  # Source first so the shared image-preflight primitives are available to the
  # gates below (ensure_docker_image delegates to them).
  # shellcheck source=../../lib/egress.sh
  source "$PROJECT_ROOT/../lib/egress.sh"

  local curl_image="${PROVEO_EGRESS_TEST_IMAGE:-curlimages/curl:8.10.1}"
  if ! ensure_docker_image "$curl_image"; then
    skip_test "egress integration: test curl image" "missing $curl_image; set PROVEO_EGRESS_PULL=1 to pull"
    return 0
  fi
  CURL_IMAGE="$curl_image"

  local tmp
  tmp="$(mktemp -d)"

  TESTS_RUN=$((TESTS_RUN + 1))
  if docker run --rm --network bridge "$curl_image" -fsSL --max-time 20 https://example.com >/dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${NC} [%d] [integration/broker] direct HTTP(S) egress succeeds on bridge\n" "$TESTS_RUN"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES+=("[integration/broker] direct HTTP(S) egress succeeds on bridge")
    printf "${RED}FAIL${NC} [%d] [integration/broker] direct HTTP(S) egress failed\n" "$TESTS_RUN"
  fi

  unset PROVEO_EGRESS_SESSION_ID PROVEO_EGRESS_DIR
  PROVEO_EGRESS_SESSION="integration-proxy-$$"
  if proveo_egress_prepare proxy integration "$tmp/reports"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    if docker run --rm "${PROVEO_EGRESS_AGENT_DOCKER_ARGS[@]}" "$curl_image" -fsSL --retry 25 --retry-connrefused --retry-delay 2 --max-time 30 https://example.com >/dev/null 2>&1; then
      TESTS_PASSED=$((TESTS_PASSED + 1))
      printf "${GREEN}PASS${NC} [%d] [integration/proxy] HTTP(S) succeeds through Squid\n" "$TESTS_RUN"
    else
      TESTS_FAILED=$((TESTS_FAILED + 1))
      FAILURES+=("[integration/proxy] HTTP(S) succeeds through Squid")
      printf "${RED}FAIL${NC} [%d] [integration/proxy] HTTP(S) through Squid failed\n" "$TESTS_RUN"
    fi

    TESTS_RUN=$((TESTS_RUN + 1))
    if docker run --rm "${PROVEO_EGRESS_AGENT_DOCKER_ARGS[@]}" "$curl_image" --noproxy '*' -fsSL --max-time 10 https://example.com >/dev/null 2>&1; then
      TESTS_FAILED=$((TESTS_FAILED + 1))
      FAILURES+=("[integration/proxy] direct proxy bypass fails")
      printf "${RED}FAIL${NC} [%d] [integration/proxy] direct bypass unexpectedly succeeded\n" "$TESTS_RUN"
    else
      TESTS_PASSED=$((TESTS_PASSED + 1))
      printf "${GREEN}PASS${NC} [%d] [integration/proxy] direct proxy bypass fails\n" "$TESTS_RUN"
    fi

    # Multiple levels of blocked egress through the Squid enforcement proxy.
    assert_egress_blocked "[integration/proxy] private RFC1918 destination is denied" \
      -fsS --max-time 10 http://10.255.255.1/
    assert_egress_blocked "[integration/proxy] cloud-metadata SSRF (169.254.169.254) is denied" \
      -fsS --max-time 10 http://169.254.169.254/latest/meta-data/
    assert_egress_blocked "[integration/proxy] non-web port (:22) is denied" \
      -fsS --max-time 10 http://example.com:22/
    assert_egress_blocked "[integration/proxy] visible HTTP write method (POST) is denied" \
      -fsS -X POST --max-time 10 http://example.com/

    # The post-run report must reflect what was actually denied. Let Squid flush
    # its access log (wait for the last attempt to land), build the report, then
    # assert every blocked destination attempted above appears in the denied
    # list and the allowed external op appears under allowed.
    local waited=0
    until grep -qF "POST http://example.com" "$PROVEO_EGRESS_DIR/squid/logs/access.log" 2>/dev/null || (( waited >= 10 )); do
      sleep 1; waited=$((waited + 1))
    done
    proveo_egress_report >/dev/null 2>&1
    local report="$PROVEO_EGRESS_DIR/report.txt"
    assert_file_contains "[integration/proxy] report records the allowed external op" "$report" "example.com:443"
    local denied_attempt
    for denied_attempt in "10.255.255.1" "169.254.169.254" "example.com:22" "POST example.com"; do
      assert_file_contains "[integration/proxy] report lists denied attempt: $denied_attempt" "$report" "$denied_attempt"
    done
    assert_file_contains "[integration/proxy] denied attempts recorded in report.json" "$PROVEO_EGRESS_DIR/report.json" "169.254.169.254"
  else
    egress_fail "[integration/proxy] prepare egress topology"
  fi
  proveo_egress_cleanup

  # Gate on the locally-built mitmproxy image, but DON'T early-return — the
  # local-model integration below must still run when mitmproxy isn't built.
  local mitm_image="${PROVEO_MITMPROXY_IMAGE:-proveo/mitmproxy:latest}"
  if ! proveo_egress_image_present "$mitm_image"; then
    skip_test "egress integration: firewall" "missing $mitm_image; run: defs/sidecars/mitmproxy/build.sh"
  else
  unset PROVEO_EGRESS_SESSION_ID PROVEO_EGRESS_DIR
  PROVEO_EGRESS_SESSION="integration-firewall-$$"
  if proveo_egress_prepare firewall integration "$tmp/reports"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    if docker run --rm "${PROVEO_EGRESS_AGENT_DOCKER_ARGS[@]}" "$curl_image" -fsSL --retry 25 --retry-connrefused --retry-delay 2 --max-time 30 https://example.com >/dev/null 2>&1; then
      TESTS_PASSED=$((TESTS_PASSED + 1))
      printf "${GREEN}PASS${NC} [%d] [integration/firewall] HTTP(S) succeeds through mitmproxy then Squid (CA trusted)\n" "$TESTS_RUN"
    else
      TESTS_FAILED=$((TESTS_FAILED + 1))
      FAILURES+=("[integration/firewall] HTTP(S) succeeds through mitmproxy then Squid")
      printf "${RED}FAIL${NC} [%d] [integration/firewall] HTTP(S) chain failed\n" "$TESTS_RUN"
    fi

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ -s "$PROVEO_EGRESS_DIR/mitmproxy/flows/flows.ndjson" ]]; then
      TESTS_PASSED=$((TESTS_PASSED + 1))
      printf "${GREEN}PASS${NC} [%d] [integration/firewall] mitmproxy recorded a decrypted flow\n" "$TESTS_RUN"
    else
      TESTS_FAILED=$((TESTS_FAILED + 1))
      FAILURES+=("[integration/firewall] mitmproxy recorded a decrypted flow")
      printf "${RED}FAIL${NC} [%d] [integration/firewall] missing mitmproxy flow export\n" "$TESTS_RUN"
    fi
  else
    egress_fail "[integration/firewall] prepare egress topology"
  fi
  proveo_egress_cleanup
  fi

  run_local_model_integration

  run_provider_allowlist_integration

  rm -rf "$tmp"
}

echo "Testing egress mode contracts..."
echo "Level 1: static policy contracts"
SQUID_CONF="$PROJECT_ROOT/../sidecars/squid-proxy/squid.conf"
assert_file_contains "[policy] Squid documents HTTP/HTTPS-only protocol allowlist" "$SQUID_CONF" "Protocol allowlist: HTTP and HTTPS only"
assert_file_contains "[policy] Squid allows HTTP port 80" "$SQUID_CONF" "acl Safe_ports port 80"
assert_file_contains "[policy] Squid allows HTTPS port 443" "$SQUID_CONF" "acl Safe_ports port 443"
assert_file_contains "[policy] Squid blocks non-web/raw protocols by denying non-safe ports" "$SQUID_CONF" "http_access deny !Safe_ports"
assert_file_contains "[policy] Squid allows only read-oriented visible HTTP methods by default" "$SQUID_CONF" "acl read_methods method GET HEAD OPTIONS"
assert_file_not_contains "[policy] FTP is not in the allowed protocol set" "$SQUID_CONF" "acl Safe_ports port 21"
assert_file_contains "[policy] Squid includes FireHOL-informed reserved destination defaults" "$SQUID_CONF" "include /etc/squid/firehol-blocked-nets.conf"
assert_file_contains "[policy] Squid supports optional generated FireHOL ipset ACLs" "$SQUID_CONF" "include /etc/squid/firehol-ipset.conf"
assert_file_contains "[policy] reserved defaults block cloud metadata SSRF range" "$PROJECT_ROOT/../sidecars/squid-proxy/firehol-blocked-nets.conf" "169.254.0.0/16"
assert_file_contains "[policy] reserved defaults block private RFC1918 ranges" "$PROJECT_ROOT/../sidecars/squid-proxy/firehol-blocked-nets.conf" "10.0.0.0/8"
assert_file_contains "[policy] optional FireHOL updater defaults to firehol_level1" "$PROJECT_ROOT/../sidecars/squid-proxy/update-firehol-ipsets.sh" "firehol_level1"
assert_file_contains "[policy] optional FireHOL updater generates Squid ACLs" "$PROJECT_ROOT/../sidecars/squid-proxy/update-firehol-ipsets.sh" "acl firehol_ipset dst"
assert_file_contains "[policy] any HTTPS documentation/search destination is allowed by protocol" "$SQUID_CONF" "http_access allow CONNECT SSL_ports"
assert_file_contains "[policy] any visible HTTP documentation/search read is allowed by method" "$SQUID_CONF" "http_access allow read_methods"
assert_file_contains "[policy] docs/search access is intentionally generic, not host-specific" "$SQUID_CONF" "any documentation site, search engine"
assert_file_not_contains "[policy] Pinecone docs are not hardcoded as a special case" "$SQUID_CONF" "docs.pinecone.io"
assert_file_not_contains "[policy] Google search is not hardcoded as a special case" "$SQUID_CONF" ".google.com"

echo "Level 2: dry-run Docker topology contracts"
assert_mode_contract broker
assert_mode_contract proxy
assert_mode_contract firewall

echo "Level 2b: local-model sidecar contracts"
assert_local_model_contract broker
assert_local_model_contract proxy
assert_local_model_contract firewall

echo "Level 2c: post-run egress report"
assert_egress_report_ranking

echo "Level 2d: provider allowlist + key auto-detection"
assert_provider_allowlist_contracts

echo "Level 3: gated Docker integration contracts"
if [[ "${PROVEO_EGRESS_INTEGRATION:-0}" != "1" ]]; then
  skip_test "egress integration: broker allows arbitrary mock protocol egress; proxy blocks non-web protocols; firewall captures decrypted HTTP(S) attempts in mitmproxy flows" "set PROVEO_EGRESS_INTEGRATION=1 to run Docker network integration tests"
else
  run_live_egress_integration
fi

# Propagate failures to the caller (the runner uses `set -e`). Without this a
# stale assertion is printed but the script exits 0 and the failure is masked.
echo
printf 'egress contracts — failed: %d\n' "${TESTS_FAILED:-0}"
if (( ${TESTS_FAILED:-0} > 0 )); then
  printf 'Failed egress contracts:\n'
  for _f in ${FAILURES[@]+"${FAILURES[@]}"}; do printf '  - %s\n' "$_f"; done
  exit 1
fi
