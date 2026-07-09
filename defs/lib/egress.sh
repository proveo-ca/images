#!/usr/bin/env bash
# SPEC: _spec/defs/claudecode/claudecode-egress-topology.puml
# Shared Docker egress lifecycle for agent harnesses.
# Modes:
#   broker              direct bridge egress (container boundary only; ex-open)
#   proxy               agent -> Squid -> internet
#   firewall (default)  agent -> proveo-egress (TLS MITM + credential broker) -> Squid -> internet
#
# In firewall mode the Go egress proxy (or legacy mitmproxy) is the first-hop
# inspector. It decrypts HTTPS (records method/path/host), brokers credentials,
# and forwards everything to Squid, which stays the enforcement + egress
# boundary. The agent trusts the inspector CA via standard CA env vars.

PROVEO_EGRESS_AGENT_DOCKER_ARGS=()
PROVEO_EGRESS_CLEANUP_CONTAINERS=()
PROVEO_EGRESS_CLEANUP_NETWORKS=()
PROVEO_EGRESS_SESSION_ID=""
PROVEO_EGRESS_DIR=""
PROVEO_EGRESS_MODE=""
PROVEO_EGRESS_PROVIDER_RESOLVED=""
# Credential broker (firewall mode + Go inspector): the single resolved
# provider and the host path to the 0600 secret env-file mounted into the proxy.
# See _spec/paradigms.md (Credential Boundary) and plans/01, plans/04.
PROVEO_EGRESS_BROKER_PROVIDER=""
PROVEO_EGRESS_BROKER_ENVFILE_HOST=""

proveo_egress_defs_dir() {
  if [[ -n "${PROVEO_DEFS_DIR:-}" ]]; then
    printf '%s\n' "$PROVEO_DEFS_DIR"
    return 0
  fi
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

proveo_egress_new_session_id() {
  printf 'proveo-%s-%s' "$(date +%Y%m%d%H%M%S)" "$$"
}

proveo_egress_docker() {
  docker "$@"
}

# --- Image preflight (shared by the lifecycle and the tests) ---------------

# True if the image already exists locally (no network call).
proveo_egress_image_present() {
  proveo_egress_docker image inspect "$1" >/dev/null 2>&1
}

# Ensure ONE image is ready for `docker run`. Every missing image is pulled
# first — proveo/* images are published to Docker Hub by `mise deploy`, so the
# consumer path is a pull; a failed proveo/* pull falls back to local-build
# guidance (maintainers iterating pre-publish). Set PROVEO_EGRESS_PULL=1 to
# force-refresh an already-present image. Returns non-zero with an actionable
# message when the image can't be readied.
proveo_egress_ensure_image() {
  local image="$1"
  if proveo_egress_image_present "$image" \
     && [[ ! "${PROVEO_EGRESS_PULL:-0}" =~ ^(1|true|yes|on)$ ]]; then
    return 0
  fi
  echo "📥 ensuring image: $image" >&2
  proveo_egress_docker pull "$image" >/dev/null 2>&1 && return 0
  # Pull failed — tolerate only if a usable local copy already exists.
  proveo_egress_image_present "$image" && { echo "⚠️  using local $image (pull failed)" >&2; return 0; }
  if [[ "$image" == proveo/* ]]; then
    local target="${image#proveo/}"
    echo "❌ image not built: $image (pull failed) — run: defs/sidecars/${target%%:*}/build.sh, or publish it with: mise deploy" >&2
    return 1
  fi
  echo "❌ image unavailable: $image (pull failed)" >&2
  return 1
}

# Preflight every sidecar image a mode/local-model combination needs, BEFORE any
# network or container is created — so a missing image fails fast instead of
# half-building the topology. Returns non-zero if any image can't be readied.
proveo_egress_ensure_images() {
  local mode="$1" local_model="$2"
  local -a images=()
  case "$mode" in
    proxy)
      images+=("${PROVEO_SQUID_PROXY_IMAGE:-ubuntu/squid:latest}")
      ;;
    firewall)
      images+=("${PROVEO_SQUID_PROXY_IMAGE:-ubuntu/squid:latest}")
      # Inspector: the Go egress proxy (default) or the legacy mitmproxy sidecar.
      if [[ "${PROVEO_EGRESS_INSPECTOR:-go}" == "mitmproxy" ]]; then
        images+=("${PROVEO_MITMPROXY_IMAGE:-proveo/mitmproxy:latest}")
      else
        images+=("${PROVEO_EGRESS_PROXY_IMAGE:-proveo/egress-proxy:latest}")
      fi
      ;;
  esac
  [[ -n "$local_model" ]] && images+=("${PROVEO_OLLAMA_IMAGE:-ollama/ollama:latest}")

  local img rc=0
  if (( ${#images[@]} )); then
    for img in "${images[@]}"; do
      proveo_egress_ensure_image "$img" || rc=1
    done
  fi
  return "$rc"
}

proveo_egress_network_create() {
  local name="$1" internal_flag="${2:-}"
  local args=("network" "create" "--label" "proveo.egress.session=${PROVEO_EGRESS_SESSION_ID}")
  if [[ "$internal_flag" == "internal" ]]; then
    args+=("--internal")
  fi
  args+=("$name")
  proveo_egress_docker "${args[@]}" >/dev/null
  PROVEO_EGRESS_CLEANUP_NETWORKS+=("$name")
}

proveo_egress_container_name() {
  local role="$1"
  printf '%s-%s' "$PROVEO_EGRESS_SESSION_ID" "$role"
}

proveo_egress_copy_squid_config() {
  local defs_dir squid_config_dir
  defs_dir="$(proveo_egress_defs_dir)"
  squid_config_dir="$PROVEO_EGRESS_DIR/squid/config"
  mkdir -p "$squid_config_dir"
  cp "$defs_dir/sidecars/squid-proxy/squid.conf" "$squid_config_dir/squid.conf"
  cp "$defs_dir/sidecars/squid-proxy/firehol-blocked-nets.conf" "$squid_config_dir/firehol-blocked-nets.conf"
  cp "$defs_dir/sidecars/squid-proxy/firehol-ipset.conf" "$squid_config_dir/firehol-ipset.conf"
  cp "$defs_dir/sidecars/squid-proxy/provider-allow.conf" "$squid_config_dir/provider-allow.conf"
  proveo_egress_write_provider_allow "$squid_config_dir/provider-allow.conf" || return 1
}

# Resolve and run the Go egress helper — the SINGLE SOURCE for provider knowledge
# (detection + Squid write-pin ACL, in internal/provider). The Bash equivalents
# were retired here; this delegates. Resolution order: PROVEO_EGRESS_BIN, then
# `proveo-egress` on PATH (the shipped harness bakes it), then a repo dev build.
proveo_egress_run_bin() {
  if [[ -n "${PROVEO_EGRESS_BIN:-}" && -x "${PROVEO_EGRESS_BIN}" ]]; then
    "$PROVEO_EGRESS_BIN" "$@"; return
  fi
  if command -v proveo-egress >/dev/null 2>&1; then
    proveo-egress "$@"; return
  fi
  local repo_root; repo_root="$(cd "$(proveo_egress_defs_dir)/.." && pwd)"
  if command -v go >/dev/null 2>&1 && [[ -f "$repo_root/go.mod" ]]; then
    ( cd "$repo_root" && go run ./cmd/proveo-egress "$@" ); return
  fi
  echo "❌ proveo-egress not found: set PROVEO_EGRESS_BIN or build it (go build ./cmd/proveo-egress)" >&2
  return 127
}

# Infer the provider(s) from the API keys present — delegates to the Go registry.
# The env (and PROVEO_EGRESS_ENV_FILE, via the binary's merged lookup) is the
# intent; echoes a space-separated provider list (possibly empty).
proveo_egress_detect_providers() {
  proveo_egress_run_bin detect
}

# Generate the provider allowlist include. Provider(s) come from an explicit
# PROVEO_EGRESS_PROVIDER (override) or, by default, are auto-detected from the
# API keys present in the env/.env. With none resolved it stays a no-op (squid
# keeps its read-allow/write-deny default). With one or more, it pins visible
# write methods to ONLY those provider endpoints and denies them to every other
# host. NOTE: this is enforced for cleartext HTTP and (in firewall
# mode) for decrypted HTTPS. In plain proxy mode Squid cannot see the method
# inside an HTTPS CONNECT tunnel, so HTTPS writes to other hosts are NOT blocked
# — full write-pinning requires firewall (TLS interception).
proveo_egress_write_provider_allow() {
  local file="$1"
  local prov="${PROVEO_EGRESS_PROVIDER_RESOLVED:-${PROVEO_EGRESS_PROVIDER:-}}"
  # Delegates to the Go registry (internal/egress.ProviderAllowConf); the Bash
  # generator + provider ACL map were retired. Forward the custom-domains var
  # explicitly — the Go binary is a subprocess and only sees passed/exported env
  # (the Bash generator used to read it as a plain shell var).
  if ! PROVEO_EGRESS_PROVIDER="$prov" \
       PROVEO_EGRESS_PROVIDER_DOMAINS="${PROVEO_EGRESS_PROVIDER_DOMAINS:-}" \
       proveo_egress_run_bin provider-allow >"$file"; then
    return 1
  fi
  if [[ "${PROVEO_EGRESS_MODE:-}" == "firewall" ]]; then
    echo "🔒 Provider writes pinned — HTTPS decrypted; writes to other hosts blocked (web reads open)" >&2
  elif [[ -n "$prov" && "$prov" != "none" ]]; then
    echo "🔒 Provider allowlist set (web reads stay open)" >&2
    echo "⚠️  proxy mode does NOT inspect HTTPS: writes/exfiltration over HTTPS to non-provider hosts are NOT blocked. Use --egress-mode firewall for enforced write-pinning." >&2
  fi
}

proveo_egress_prepare_logs() {
  mkdir -p \
    "$PROVEO_EGRESS_DIR/mitmproxy/confdir" \
    "$PROVEO_EGRESS_DIR/mitmproxy/flows" \
    "$PROVEO_EGRESS_DIR/squid/config" \
    "$PROVEO_EGRESS_DIR/squid/logs" \
    "$PROVEO_EGRESS_DIR/guard"
  : >"$PROVEO_EGRESS_DIR/guard/reject.log"
}

proveo_egress_write_metadata() {
  cat >"$PROVEO_EGRESS_DIR/metadata.env" <<EOF
PROVEO_EGRESS_SESSION_ID=$PROVEO_EGRESS_SESSION_ID
PROVEO_EGRESS_MODE=$PROVEO_EGRESS_MODE
PROVEO_EGRESS_DIR=$PROVEO_EGRESS_DIR
PROVEO_EGRESS_PROVIDER=${PROVEO_EGRESS_PROVIDER_RESOLVED:-${PROVEO_EGRESS_PROVIDER:-none}}
EOF
}

proveo_egress_start_squid() {
  local internal_network="$1" egress_network="$2"
  local image name
  image="${PROVEO_SQUID_PROXY_IMAGE:-ubuntu/squid:latest}"
  name="$(proveo_egress_container_name squid)"
  proveo_egress_copy_squid_config
  PROVEO_EGRESS_CLEANUP_CONTAINERS+=("$name")
  if ! proveo_egress_docker run -d --rm \
      --name "$name" \
      --label "proveo.egress.session=${PROVEO_EGRESS_SESSION_ID}" \
      --network "$egress_network" \
      -v "$PROVEO_EGRESS_DIR/squid/config:/etc/squid:ro" \
      -v "$PROVEO_EGRESS_DIR/squid/logs:/var/log/squid" \
      "$image" >/dev/null; then
    echo "❌ failed to start Squid sidecar ($image)" >&2
    return 1
  fi
  proveo_egress_docker network connect --alias squid "$internal_network" "$name"
}

proveo_egress_start_mitm() {
  local network="$1" upstream_network="$2"
  local image name confdir flows_dir
  image="${PROVEO_MITMPROXY_IMAGE:-proveo/mitmproxy:latest}"
  name="$(proveo_egress_container_name mitm)"
  confdir="$PROVEO_EGRESS_DIR/mitmproxy/confdir"
  flows_dir="$PROVEO_EGRESS_DIR/mitmproxy/flows"

  # No config file to seed: upstream is a flag, so the chain is fail-closed by
  # construction. mitmproxy generates its CA into the mounted confdir on start.
  PROVEO_EGRESS_CLEANUP_CONTAINERS+=("$name")
  if ! proveo_egress_docker run -d --rm \
      --name "$name" \
      --label "proveo.egress.session=${PROVEO_EGRESS_SESSION_ID}" \
      --network "$network" \
      --network-alias mitm \
      -e "PROVEO_MITM_UPSTREAM=http://squid:3128" \
      -e "PROVEO_MITM_PORT=8888" \
      -e "PROVEO_MITM_CONFDIR=/mitmproxy-confdir" \
      -e "PROVEO_MITM_FLOWS=/flows" \
      -v "$confdir:/mitmproxy-confdir" \
      -v "$flows_dir:/flows" \
      "$image" >/dev/null; then
    echo "❌ failed to start mitmproxy sidecar ($image)" >&2
    return 1
  fi
  proveo_egress_docker network connect "$upstream_network" "$name"
}

# Candidate provider-key env-var names the broker may inject. Mirrors the Go
# provider registry (internal/provider) and the detection list above. TRANSITIONAL
# duplication: it collapses into the Go registry once host orchestration moves to
# Go (Plan 4 Ph1). Only the NAMES appear here; values are read from the env.
proveo_egress_broker_key_names() {
  printf '%s\n' \
    ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN OPENAI_API_KEY OPENROUTER_API_KEY \
    GROQ_API_KEY MISTRAL_API_KEY XAI_API_KEY PERPLEXITY_API_KEY TOGETHER_API_KEY \
    FIREWORKS_API_KEY GMI_API_KEY COHERE_API_KEY CURSOR_API_KEY GEMINI_API_KEY GOOGLE_API_KEY
}

# Prepare the credential broker for the Go inspector: when exactly one provider
# is resolved and the broker is not disabled, write the provider keys present in
# the host env (and, if set, PROVEO_EGRESS_ENV_FILE / a project .env on the host)
# to a 0600 file OUTSIDE every agent mount, and record the provider name. The Go
# proxy resolves which key/header to inject via its provider registry. Keys are
# never mounted into the agent in firewall mode. Sets
# PROVEO_EGRESS_BROKER_{PROVIDER,ENVFILE_HOST}.
proveo_egress_prepare_broker_secrets() {
  case "$(printf '%s' "${PROVEO_CREDENTIAL_BROKER:-on}" | tr '[:upper:]' '[:lower:]')" in
    off|0|no|false|disable|disabled) return 0 ;;
  esac
  # Injecting one auth header is unambiguous only with a single pinned provider.
  local -a providers
  # shellcheck disable=SC2206
  providers=(${PROVEO_EGRESS_PROVIDER_RESOLVED//,/ })
  if (( ${#providers[@]} != 1 )); then
    (( ${#providers[@]} > 1 )) && echo "ℹ️  credential broker skipped: multiple providers resolved (${providers[*]}); pin one with PROVEO_EGRESS_PROVIDER" >&2
    return 0
  fi

  local inject_dir="$PROVEO_EGRESS_DIR/inject"
  local envfile="$inject_dir/broker.env"
  mkdir -p "$inject_dir"
  chmod 700 "$inject_dir" 2>/dev/null || true

  # Host-side .env for keys not exported into the shell (never mounted into agent).
  local host_env_file="${PROVEO_EGRESS_ENV_FILE:-}"
  if [[ -z "$host_env_file" ]]; then
    if [[ -f "${PWD}/.env" ]]; then
      host_env_file="${PWD}/.env"
    elif [[ -f "${PROVEO_INPUT_DIR:-}/.env" ]]; then
      host_env_file="${PROVEO_INPUT_DIR}/.env"
    fi
  fi

  local name val wrote=0
  (
    umask 077
    : >"$envfile"
    while IFS= read -r name; do
      val="${!name:-}"
      if [[ -z "$val" && -n "$host_env_file" ]]; then
        # Prefer defs/lib/env-mount.sh helper when sourced; else inline python.
        if command -v proveo_env_file_get >/dev/null 2>&1; then
          val="$(proveo_env_file_get "$name" "$host_env_file" 2>/dev/null || true)"
        else
          val="$(python3 - "$name" "$host_env_file" <<'PY' 2>/dev/null || true
import sys
key, path = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[7:].lstrip()
            if "=" not in line:
                continue
            k, _, v = line.partition("=")
            if k.strip() != key:
                continue
            v = v.strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                v = v[1:-1]
            print(v)
            raise SystemExit(0)
except OSError:
    pass
PY
)"
        fi
      fi
      [[ -n "$val" ]] && printf '%s=%s\n' "$name" "$val" >>"$envfile"
    done < <(proveo_egress_broker_key_names)
    true  # a `while read` loop ends non-zero at EOF; keep the subshell exit 0
  )
  chmod 600 "$envfile" 2>/dev/null || true
  if [[ -s "$envfile" ]]; then wrote=1; fi

  PROVEO_EGRESS_BROKER_PROVIDER="${providers[0]}"
  if (( wrote )); then
    PROVEO_EGRESS_BROKER_ENVFILE_HOST="$envfile"
    echo "🔑 Credential broker: provider '${PROVEO_EGRESS_BROKER_PROVIDER}' — injecting at the proxy, stripping credentials off-provider" >&2
  else
    rm -f "$envfile" 2>/dev/null || true
    echo "🔒 Credential broker: provider '${PROVEO_EGRESS_BROKER_PROVIDER}' has no host-env key to inject; stripping off-provider + provider pass-through (put the key in your host env or PROVEO_EGRESS_ENV_FILE for full isolation)" >&2
  fi
}

# Start the Go egress inspection proxy (proveo-egress) as the agent's first hop.
# Replaces proveo_egress_start_mitm on the default firewall path: it
# TLS-terminates with a generated CA (written to the same confdir path the CA
# wait watches), records flows to the same NDJSON path the dashboard reads,
# brokers credentials, and forwards to Squid upstream. Runs as the invoking host
# uid (not root, unlike the mitmproxy sidecar) since it only writes host-owned
# bind mounts.
proveo_egress_start_egress_proxy() {
  local network="$1" upstream_network="$2"
  local image name confdir flows_dir
  image="${PROVEO_EGRESS_PROXY_IMAGE:-proveo/egress-proxy:latest}"
  name="$(proveo_egress_container_name egress)"
  confdir="$PROVEO_EGRESS_DIR/mitmproxy/confdir"
  flows_dir="$PROVEO_EGRESS_DIR/mitmproxy/flows"

  local -a run_args=(
    run -d --rm
    --name "$name"
    --user "$(id -u):$(id -g)"
    --label "proveo.egress.session=${PROVEO_EGRESS_SESSION_ID}"
    --network "$network"
    --network-alias mitm
    -e "PROVEO_EGRESS_LISTEN=:8888"
    -e "PROVEO_EGRESS_UPSTREAM=http://squid:3128"
    -e "PROVEO_EGRESS_CA_CERT_OUT=/confdir/mitmproxy-ca-cert.pem"
    -e "PROVEO_EGRESS_FLOWS=/flows/flows.ndjson"
    -v "$confdir:/confdir"
    -v "$flows_dir:/flows"
  )
  if [[ -n "$PROVEO_EGRESS_BROKER_PROVIDER" ]]; then
    run_args+=("-e" "PROVEO_EGRESS_PROVIDER=${PROVEO_EGRESS_BROKER_PROVIDER}")
  fi
  if [[ -n "$PROVEO_EGRESS_BROKER_ENVFILE_HOST" ]]; then
    run_args+=(
      "-e" "PROVEO_EGRESS_BROKER_ENVFILE=/broker/broker.env"
      "-v" "$(dirname "$PROVEO_EGRESS_BROKER_ENVFILE_HOST"):/broker:ro"
    )
  fi

  PROVEO_EGRESS_CLEANUP_CONTAINERS+=("$name")
  if ! proveo_egress_docker "${run_args[@]}" "$image" >/dev/null; then
    echo "❌ failed to start egress proxy sidecar ($image)" >&2
    return 1
  fi
  proveo_egress_docker network connect "$upstream_network" "$name"
}

# Wait for mitmproxy to generate its CA cert so the agent can trust it.
# Prints the host path to the CA cert on success; returns non-zero on timeout.
proveo_egress_wait_for_mitm_ca() {
  local ca="$PROVEO_EGRESS_DIR/mitmproxy/confdir/mitmproxy-ca-cert.pem"
  local waited=0 limit="${PROVEO_MITM_CA_WAIT_SECS:-20}"
  while [[ ! -s "$ca" ]]; do
    if (( waited >= limit )); then
      echo "timed out waiting for mitmproxy CA at $ca" >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  printf '%s\n' "$ca"
}

# Optional local-model sidecar: an Ollama server attached to the agent network.
# It serves the host's already-pulled models read-only, so no model is
# re-downloaded and the sidecar needs no internet of its own — it just answers
# the agent on the internal network. Works alongside any egress mode.
proveo_egress_start_ollama() {
  local network="$1"
  local image name models_dir
  image="${PROVEO_OLLAMA_IMAGE:-ollama/ollama:latest}"
  name="$(proveo_egress_container_name ollama)"
  models_dir="${PROVEO_OLLAMA_MODELS_DIR:-$HOME/.ollama/models}"
  PROVEO_EGRESS_CLEANUP_CONTAINERS+=("$name")
  if ! proveo_egress_docker run -d --rm \
      --name "$name" \
      --label "proveo.egress.session=${PROVEO_EGRESS_SESSION_ID}" \
      --network "$network" \
      --network-alias ollama \
      -e "OLLAMA_HOST=0.0.0.0:11434" \
      -e "OLLAMA_MODELS=/models" \
      -v "$models_dir:/models:ro" \
      "$image" >/dev/null; then
    echo "❌ failed to start Ollama sidecar ($image)" >&2
    return 1
  fi
}

# Point the agent's model env at the Ollama sidecar and keep that traffic off
# the egress proxy via NO_PROXY, so the local model is reachable while every
# other destination stays subject to Squid policy. Model names follow the
# project's ARCHITECT/EDITOR/SMALL bridge convention (litellm `ollama/<model>`).
proveo_egress_local_model_args() {
  local model="$1" base="http://ollama:11434"
  PROVEO_EGRESS_AGENT_DOCKER_ARGS+=(
    "-e" "PROVEO_LOCAL_MODEL=${model}"
    "-e" "OLLAMA_HOST=${base}"
    "-e" "OLLAMA_API_BASE=${base}"
    "-e" "OPENAI_BASE_URL=${base}/v1"
    "-e" "OPENAI_API_KEY=ollama"
    "-e" "ARCHITECT_MODEL=ollama/${model}"
    "-e" "EDITOR_MODEL=ollama/${model}"
    "-e" "SMALL_MODEL=ollama/${model}"
    "-e" "NO_PROXY=ollama,localhost,127.0.0.1"
    "-e" "no_proxy=ollama,localhost,127.0.0.1"
  )
}

proveo_egress_env_args() {
  local proxy_url="$1"
  PROVEO_EGRESS_AGENT_DOCKER_ARGS+=(
    "-e" "PROVEO_EGRESS_SESSION_ID=${PROVEO_EGRESS_SESSION_ID}"
    "-e" "PROVEO_EGRESS_MODE=${PROVEO_EGRESS_MODE}"
    "-e" "HTTP_PROXY=${proxy_url}"
    "-e" "HTTPS_PROXY=${proxy_url}"
    "-e" "http_proxy=${proxy_url}"
    "-e" "https_proxy=${proxy_url}"
  )
}

proveo_egress_prepare() {
  local mode="$1" agent_name="$2" output_dir="$3"
  PROVEO_EGRESS_MODE="$mode"
  PROVEO_EGRESS_SESSION_ID="${PROVEO_EGRESS_SESSION_ID:-${PROVEO_EGRESS_SESSION:-$(proveo_egress_new_session_id)}}"
  PROVEO_EGRESS_DIR="${PROVEO_EGRESS_DIR:-$output_dir/egress/$PROVEO_EGRESS_SESSION_ID}"
  PROVEO_EGRESS_AGENT_DOCKER_ARGS=()

  local safe_agent agent_network enforce_network egress_network local_model
  safe_agent="${agent_name//[^a-zA-Z0-9_.-]/-}"
  local_model="${PROVEO_LOCAL_MODEL:-}"

  # Resolve which provider(s) egress will be pinned to: an explicit override if
  # set, else auto-detected from the API keys present. Prefer an explicit
  # PROVEO_EGRESS_ENV_FILE; otherwise a host-side project .env (never mounted
  # into the agent in firewall) so keys not exported into the shell still count.
  if [[ -z "${PROVEO_EGRESS_ENV_FILE:-}" ]]; then
    if [[ -f "${PWD}/.env" ]]; then
      export PROVEO_EGRESS_ENV_FILE="${PWD}/.env"
    elif [[ -f "${PROVEO_INPUT_DIR:-}/.env" ]]; then
      export PROVEO_EGRESS_ENV_FILE="${PROVEO_INPUT_DIR}/.env"
    fi
  fi
  PROVEO_EGRESS_PROVIDER_RESOLVED="${PROVEO_EGRESS_PROVIDER:-}"
  if [[ -z "$PROVEO_EGRESS_PROVIDER_RESOLVED" || "$PROVEO_EGRESS_PROVIDER_RESOLVED" == none ]]; then
    PROVEO_EGRESS_PROVIDER_RESOLVED="$(proveo_egress_detect_providers)"
  fi

  # A pinned provider is enforced by Squid, which only exists in proxy/broker
  # modes. An EXPLICIT provider in broker mode is a misconfig (nothing enforces the
  # allowlist) — refuse rather than imply containment. Auto-detection stays quiet
  # in broker mode (no enforcement proxy to apply it to).
  if [[ -n "${PROVEO_EGRESS_PROVIDER:-}" && "${PROVEO_EGRESS_PROVIDER}" != "none" && "$mode" == "broker" ]]; then
    echo "❌ PROVEO_EGRESS_PROVIDER requires --egress-mode proxy or firewall (broker has no enforcement proxy)" >&2
    return 1
  fi

  # Preflight all sidecar images up front so a missing/unbuilt image fails fast
  # with an actionable message instead of half-building the topology.
  if ! proveo_egress_ensure_images "$mode" "$local_model"; then
    echo "❌ egress preflight failed: required image(s) not ready" >&2
    return 1
  fi

  case "$mode" in
    broker)
      if [[ -n "$local_model" ]]; then
        # Name-based DNS is needed to reach the Ollama sidecar, which the default
        # bridge lacks. Use a user-defined bridge (still internet-capable) so the
        # agent keeps open egress and can resolve the sidecar by alias.
        agent_network="${PROVEO_EGRESS_SESSION_ID}-${safe_agent}-broker-net"
        proveo_egress_network_create "$agent_network" ""
        proveo_egress_start_ollama "$agent_network" || return 1
        PROVEO_EGRESS_AGENT_DOCKER_ARGS+=("--network" "$agent_network")
        proveo_egress_local_model_args "$local_model"
        echo "🛡️  Egress mode: $mode"
        echo "🧠 Local model: ollama/${local_model} via ollama sidecar"
        return 0
      fi
      PROVEO_EGRESS_AGENT_DOCKER_ARGS+=("--network=bridge" "--add-host=host.docker.internal:127.0.0.1")
      return 0
      ;;
    proxy|firewall)
      proveo_egress_prepare_logs
      proveo_egress_write_metadata
      ;;
    *)
      echo "unknown egress mode: $mode" >&2
      return 1
      ;;
  esac

  if [[ "$mode" == "proxy" ]]; then
    agent_network="${PROVEO_EGRESS_SESSION_ID}-${safe_agent}-squid-net"
    egress_network="${PROVEO_EGRESS_SESSION_ID}-squid-egress-net"
    proveo_egress_network_create "$agent_network" internal
    proveo_egress_network_create "$egress_network" ""
    proveo_egress_start_squid "$agent_network" "$egress_network"
    PROVEO_EGRESS_AGENT_DOCKER_ARGS+=("--network" "$agent_network")
    PROVEO_EGRESS_AGENT_DOCKER_ARGS+=("-e" "ENFORCEMENT_PROXY=http://squid:3128")
    proveo_egress_env_args "http://squid:3128"
  else
    agent_network="${PROVEO_EGRESS_SESSION_ID}-${safe_agent}-mitm-net"
    enforce_network="${PROVEO_EGRESS_SESSION_ID}-mitm-squid-net"
    egress_network="${PROVEO_EGRESS_SESSION_ID}-squid-egress-net"
    proveo_egress_network_create "$agent_network" internal
    proveo_egress_network_create "$enforce_network" internal
    proveo_egress_network_create "$egress_network" ""
    proveo_egress_start_squid "$enforce_network" "$egress_network"
    # Inspector first hop: the Go egress proxy (default; TLS-terminate + record +
    # credential broker) or the legacy Python mitmproxy sidecar.
    if [[ "${PROVEO_EGRESS_INSPECTOR:-go}" == "mitmproxy" ]]; then
      proveo_egress_start_mitm "$agent_network" "$enforce_network"
    else
      proveo_egress_prepare_broker_secrets
      proveo_egress_start_egress_proxy "$agent_network" "$enforce_network"
    fi
    PROVEO_EGRESS_AGENT_DOCKER_ARGS+=("--network" "$agent_network")
    PROVEO_EGRESS_AGENT_DOCKER_ARGS+=("-e" "INSPECT_PROXY=http://mitm:8888")
    PROVEO_EGRESS_AGENT_DOCKER_ARGS+=("-e" "ENFORCEMENT_PROXY=http://squid:3128")
    proveo_egress_env_args "http://mitm:8888"

    # Trust mitmproxy's CA so HTTPS interception works end to end. Every agent
    # request terminates at mitmproxy, so pointing all CA env vars at the
    # generated cert is both sufficient and correct (no host store changes).
    local mitm_ca
    if mitm_ca="$(proveo_egress_wait_for_mitm_ca)"; then
      PROVEO_EGRESS_AGENT_DOCKER_ARGS+=(
        "-v" "${mitm_ca}:/etc/proveo/mitmproxy-ca-cert.pem:ro"
        "-e" "PROVEO_EGRESS_CA_CERT=/etc/proveo/mitmproxy-ca-cert.pem"
        "-e" "SSL_CERT_FILE=/etc/proveo/mitmproxy-ca-cert.pem"
        "-e" "REQUESTS_CA_BUNDLE=/etc/proveo/mitmproxy-ca-cert.pem"
        "-e" "NODE_EXTRA_CA_CERTS=/etc/proveo/mitmproxy-ca-cert.pem"
        "-e" "CURL_CA_BUNDLE=/etc/proveo/mitmproxy-ca-cert.pem"
        "-e" "GIT_SSL_CAINFO=/etc/proveo/mitmproxy-ca-cert.pem"
      )
    else
      echo "⚠️  mitmproxy CA not ready; HTTPS interception may fail until it is trusted" >&2
    fi
  fi

  # Optional local model on the agent network. Its traffic bypasses the egress
  # proxy (NO_PROXY); every other destination stays policed by Squid.
  if [[ -n "$local_model" ]]; then
    proveo_egress_start_ollama "$agent_network" || return 1
    proveo_egress_local_model_args "$local_model"
    echo "🧠 Local model: ollama/${local_model} via ollama sidecar (NO_PROXY bypass)"
  fi

  echo "🛡️  Egress mode: $mode"
  echo "📁 Egress logs: $PROVEO_EGRESS_DIR"
}

# Append the shared agent Docker args to the caller's array, named by "$1".
# bash 3.2 (macOS /bin/bash) has no `local -n` namerefs, so indirect through
# eval; each element is re-quoted with %q so eval can neither word-split nor
# expand it. Dynamic scoping makes the caller's array — global, or a `local` in
# an ancestor frame — visible here, matching the old nameref behavior. The
# `+`-guard keeps an empty source array from tripping `set -u` on bash < 4.4.
proveo_egress_append_agent_args() {
  local _proveo_target="$1" _proveo_arg
  for _proveo_arg in ${PROVEO_EGRESS_AGENT_DOCKER_ARGS[@]+"${PROVEO_EGRESS_AGENT_DOCKER_ARGS[@]}"}; do
    eval "${_proveo_target}+=($(printf '%q' "$_proveo_arg"))"
  done
}

_egress_json_rows() {
  # Turn `uniq -c`-style "<count> <operation...>" lines into JSON objects.
  printf '%s\n' "$1" | awk 'NF {
    c=$1; $1=""; sub(/^ +/,""); op=$0
    gsub(/\\/,"\\\\",op); gsub(/"/,"\\\"",op)
    rows[n++]=sprintf("    {\"operation\": \"%s\", \"count\": %d}", op, c)
  } END { for (i=0;i<n;i++) printf "%s%s\n", rows[i], (i<n-1 ? "," : "") }'
}

proveo_egress_report_json() {
  local out="$1" allow="$2" deny="$3" n_allow="$4" n_deny="$5"
  {
    printf '{\n'
    printf '  "session": "%s",\n' "$PROVEO_EGRESS_SESSION_ID"
    printf '  "mode": "%s",\n' "$PROVEO_EGRESS_MODE"
    printf '  "allowed_total": %s,\n' "${n_allow:-0}"
    printf '  "denied_total": %s,\n' "${n_deny:-0}"
    printf '  "top_allowed": [\n%s\n  ],\n' "$(_egress_json_rows "$allow")"
    printf '  "top_denied": [\n%s\n  ]\n' "$(_egress_json_rows "$deny")"
    printf '}\n'
  } >"$out"
}

# After the agent container exits, summarize the Squid enforcement sidecar's
# access log into a report: the top 5 allowed network operations leaving the
# host and the top 5 denied. Allowed entries are external by construction —
# the agent reaches the internet only through Squid, and the local-model
# (ollama) sidecar bypasses it via NO_PROXY, so it never appears here.
proveo_egress_report() {
  local log="$PROVEO_EGRESS_DIR/squid/logs/access.log"
  [[ -s "$log" ]] || return 0

  local report_txt="$PROVEO_EGRESS_DIR/report.txt"
  local report_json="$PROVEO_EGRESS_DIR/report.json"

  # Squid native format: ts elapsed client code/status bytes method url ...
  # Normalize each line to "<decision>\t<METHOD> <host[:port]>", dropping
  # host-local destinations so "allowed" reflects egress outside the host.
  local rows
  rows="$(awk '
    {
      status=$4; method=$6; url=$7
      if (method=="" || url=="") next
      dst=url
      sub(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//,"",dst)   # strip scheme
      sub(/\/.*$/,"",dst)                            # strip path
      if (dst=="" || dst ~ /^(localhost|127\.|host\.docker\.internal|ollama)/) next
      decision=(status ~ /DENIED/ || status ~ /\/403$/) ? "denied" : "allowed"
      printf "%s\t%s %s\n", decision, method, dst
    }
  ' "$log")"

  local n_allow n_deny top_allow top_deny
  n_allow="$(printf '%s\n' "$rows" | awk -F'\t' '$1=="allowed"' | grep -c . || true)"
  n_deny="$(printf '%s\n' "$rows"  | awk -F'\t' '$1=="denied"'  | grep -c . || true)"
  top_allow="$(printf '%s\n' "$rows" | awk -F'\t' '$1=="allowed"{print $2}' | sort | uniq -c | sort -rn | head -5)"
  top_deny="$(printf '%s\n' "$rows"  | awk -F'\t' '$1=="denied"{print $2}'  | sort | uniq -c | sort -rn | head -5)"

  {
    echo "═══ Egress report — session ${PROVEO_EGRESS_SESSION_ID} (${PROVEO_EGRESS_MODE} mode) ═══"
    echo "allowed: ${n_allow}   denied: ${n_deny}   (source: Squid access.log)"
    echo
    echo "Top 5 ALLOWED network operations (outside the host):"
    if [[ -n "$top_allow" ]]; then printf '%s\n' "$top_allow"; else echo "     (none)"; fi
    echo
    echo "Top 5 DENIED network operations:"
    if [[ -n "$top_deny" ]]; then printf '%s\n' "$top_deny"; else echo "     (none)"; fi
  } | tee "$report_txt"

  proveo_egress_report_json "$report_json" "$top_allow" "$top_deny" "$n_allow" "$n_deny"
  echo "📝 Egress report: $report_txt"
}

proveo_egress_cleanup() {
  # Summarize allowed/denied egress before tearing anything down (the agent
  # container has already exited by the time cleanup runs).
  proveo_egress_report || true

  # The brokered secret env-file must never outlive the run, even when egress
  # artifacts are kept for inspection.
  if [[ -n "$PROVEO_EGRESS_BROKER_ENVFILE_HOST" && -f "$PROVEO_EGRESS_BROKER_ENVFILE_HOST" ]]; then
    rm -f "$PROVEO_EGRESS_BROKER_ENVFILE_HOST" 2>/dev/null || true
  fi

  if [[ "${PROVEO_KEEP_EGRESS:-0}" =~ ^(1|true|yes|on)$ ]]; then
    echo "🔎 Keeping egress sidecars/networks for session: $PROVEO_EGRESS_SESSION_ID"
    return 0
  fi

  # `+`-guard both loops: on bash < 4.4 (macOS ships 3.2) expanding an empty
  # array under `set -u` raises "unbound variable", which fires in broker mode
  # where nothing was ever registered for cleanup.
  local item
  for item in ${PROVEO_EGRESS_CLEANUP_CONTAINERS[@]+"${PROVEO_EGRESS_CLEANUP_CONTAINERS[@]}"}; do
    docker rm -f "$item" >/dev/null 2>&1 || true
  done
  for item in ${PROVEO_EGRESS_CLEANUP_NETWORKS[@]+"${PROVEO_EGRESS_CLEANUP_NETWORKS[@]}"}; do
    docker network rm "$item" >/dev/null 2>&1 || true
  done
}
