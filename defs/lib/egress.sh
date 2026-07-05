#!/usr/bin/env bash
# SPEC: _spec/defs/claudecode/claudecode-egress-topology.puml
# Shared Docker egress lifecycle for agent harnesses.
# Modes:
#   open                direct bridge egress
#   proxy               agent -> Squid -> internet
#   inspected-firewall  agent -> mitmproxy -> Squid -> internet
#
# In inspected-firewall mode mitmproxy is the first-hop inspector. It decrypts
# HTTPS (records method/path/host) and forwards everything to Squid, which stays
# the enforcement + egress boundary. The agent trusts mitmproxy's generated CA
# via standard CA env vars, so all of its TLS terminates at mitmproxy.

PROVEO_EGRESS_AGENT_DOCKER_ARGS=()
PROVEO_EGRESS_CLEANUP_CONTAINERS=()
PROVEO_EGRESS_CLEANUP_NETWORKS=()
PROVEO_EGRESS_SESSION_ID=""
PROVEO_EGRESS_DIR=""
PROVEO_EGRESS_MODE=""
PROVEO_EGRESS_PROVIDER_RESOLVED=""

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

# Ensure ONE image is ready for `docker run`. proveo/* images are built locally
# and are never pulled; everything else is pulled when missing. Set
# PROVEO_EGRESS_PULL=1 to force-refresh an already-present pullable image.
# Returns non-zero with an actionable message when the image can't be readied.
proveo_egress_ensure_image() {
  local image="$1"
  if [[ "$image" == proveo/* ]]; then
    proveo_egress_image_present "$image" && return 0
    local target="${image#proveo/}"
    echo "❌ image not built: $image — run: defs/sidecars/${target%%:*}/build.sh" >&2
    return 1
  fi
  if proveo_egress_image_present "$image" \
     && [[ ! "${PROVEO_EGRESS_PULL:-0}" =~ ^(1|true|yes|on)$ ]]; then
    return 0
  fi
  echo "📥 ensuring image: $image" >&2
  proveo_egress_docker pull "$image" >/dev/null 2>&1 && return 0
  # Pull failed — tolerate only if a usable local copy already exists.
  proveo_egress_image_present "$image" && { echo "⚠️  using local $image (pull failed)" >&2; return 0; }
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
    inspected-firewall)
      images+=("${PROVEO_SQUID_PROXY_IMAGE:-ubuntu/squid:latest}")
      images+=("${PROVEO_MITMPROXY_IMAGE:-proveo/mitmproxy:latest}")
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

# Squid ACL line(s) defining `provider_allow` for a known provider. Hyperscaler
# endpoints use tight regexes so the allowlist can't become an exfil/write hole
# to the rest of the cloud (S3, GCS, etc.) — only the inference host matches.
proveo_egress_provider_acl() {
  case "$1" in
    # --- Hyperscalers hosting open weights in-region (tight regex: only the
    #     inference host, never the rest of the cloud) ---
    bedrock)    printf 'acl provider_allow dstdom_regex (^|\\.)bedrock-runtime\\.[a-z0-9-]+\\.amazonaws\\.com$\n' ;;
    vertex)     printf 'acl provider_allow dstdom_regex (^|\\.)([a-z0-9-]+-)?aiplatform\\.googleapis\\.com$\n' ;;
    azure)      printf 'acl provider_allow dstdomain .inference.ai.azure.com .services.ai.azure.com .openai.azure.com .cognitiveservices.azure.com\n' ;;
    # --- Independent Western inference / aggregator ---
    together)   printf 'acl provider_allow dstdomain .together.xyz .together.ai\n' ;;
    fireworks)  printf 'acl provider_allow dstdomain .fireworks.ai\n' ;;
    gmi)        printf 'acl provider_allow dstdomain .gmi-serving.com\n' ;;
    openrouter) printf 'acl provider_allow dstdomain openrouter.ai .openrouter.ai\n' ;;
    # --- Trusted first-party native APIs (the destination is itself the safe
    #     provider; US/EU jurisdiction, enterprise no-train terms available) ---
    anthropic)  printf 'acl provider_allow dstdomain .anthropic.com\n' ;;
    openai)     printf 'acl provider_allow dstdomain .openai.com .api.openai.com\n' ;;
    # Cursor CLI: inference is vendor-pinned to the Cursor backend (api5/api2
    # .cursor.sh for agent/API traffic; downloads live on .cursor.com). There is
    # no custom base-URL escape hatch, so this pin covers all of its egress.
    cursor)     printf 'acl provider_allow dstdomain .cursor.sh .cursor.com\n' ;;
    xai)        printf 'acl provider_allow dstdomain .x.ai\n' ;;
    perplexity) printf 'acl provider_allow dstdomain .perplexity.ai\n' ;;
    google)     printf 'acl provider_allow dstdomain generativelanguage.googleapis.com\n' ;;
    groq)       printf 'acl provider_allow dstdomain .groq.com\n' ;;
    mistral)    printf 'acl provider_allow dstdomain .mistral.ai\n' ;;
    cohere)     printf 'acl provider_allow dstdomain .cohere.com .cohere.ai\n' ;;
    *)          return 1 ;;
  esac
}

# True if an API-key-style env var is set, considering both the current
# environment and an optional .env file (PROVEO_EGRESS_ENV_FILE) — so a key in
# the project's .env auto-selects the provider with no extra flags. Only the key
# NAME's presence is checked; values are never read or logged.
proveo_egress_key_present() {
  local name="$1"
  [[ -n "${!name:-}" ]] && return 0
  local f="${PROVEO_EGRESS_ENV_FILE:-}"
  [[ -n "$f" && -f "$f" ]] && grep -Eq "^[[:space:]]*(export[[:space:]]+)?${name}=[^[:space:]\"']" "$f"
}

# Infer the provider(s) the run will talk to from which API keys are present.
# The credential the user already has IS the intent — no flag needed. When
# several are present we allow the union (you can reach every provider you hold a
# key for, nothing else). Echoes a space-separated provider list (possibly empty).
proveo_egress_detect_providers() {
  local out=""
  proveo_egress_key_present ANTHROPIC_API_KEY   || proveo_egress_key_present CLAUDE_CODE_OAUTH_TOKEN && out="$out anthropic"
  proveo_egress_key_present CURSOR_API_KEY      && out="$out cursor"
  proveo_egress_key_present OPENAI_API_KEY      && out="$out openai"
  proveo_egress_key_present XAI_API_KEY         && out="$out xai"
  proveo_egress_key_present PERPLEXITY_API_KEY  && out="$out perplexity"
  proveo_egress_key_present GEMINI_API_KEY      || proveo_egress_key_present GOOGLE_API_KEY && out="$out google"
  proveo_egress_key_present GROQ_API_KEY        && out="$out groq"
  proveo_egress_key_present MISTRAL_API_KEY     && out="$out mistral"
  proveo_egress_key_present COHERE_API_KEY      && out="$out cohere"
  proveo_egress_key_present TOGETHER_API_KEY    && out="$out together"
  proveo_egress_key_present FIREWORKS_API_KEY   && out="$out fireworks"
  proveo_egress_key_present GMI_API_KEY         && out="$out gmi"
  proveo_egress_key_present OPENROUTER_API_KEY  && out="$out openrouter"
  proveo_egress_key_present AWS_BEARER_TOKEN_BEDROCK || proveo_egress_key_present AWS_ACCESS_KEY_ID && out="$out bedrock"
  proveo_egress_key_present AZURE_API_KEY       || proveo_egress_key_present AZURE_OPENAI_API_KEY && out="$out azure"
  proveo_egress_key_present GOOGLE_APPLICATION_CREDENTIALS && out="$out vertex"
  # shellcheck disable=SC2086
  echo $out
}

# Generate the provider allowlist include. Provider(s) come from an explicit
# PROVEO_EGRESS_PROVIDER (override) or, by default, are auto-detected from the
# API keys present in the env/.env. With none resolved it stays a no-op (squid
# keeps its read-allow/write-deny default). With one or more, it pins visible
# write methods to ONLY those provider endpoints and denies them to every other
# host. NOTE: this is enforced for cleartext HTTP and (in inspected-firewall
# mode) for decrypted HTTPS. In plain proxy mode Squid cannot see the method
# inside an HTTPS CONNECT tunnel, so HTTPS writes to other hosts are NOT blocked
# — full write-pinning requires inspected-firewall (TLS interception).
proveo_egress_write_provider_allow() {
  local file="$1"
  local providers="${PROVEO_EGRESS_PROVIDER_RESOLVED:-${PROVEO_EGRESS_PROVIDER:-}}"
  if [[ -z "$providers" ]]; then
    providers="$(proveo_egress_detect_providers)"
  fi
  providers="${providers//,/ }"
  if [[ -z "$providers" || "$providers" == none ]]; then
    printf '# No provider allowlist active (no provider pinned or API key detected).\n' >"$file"
    return 0
  fi

  local p acl_line matched="" unknown=""
  {
    echo "# Provider allowlist — resolved provider(s): $providers"
    for p in $providers; do
      if acl_line="$(proveo_egress_provider_acl "$p")"; then
        printf '%s' "$acl_line"; matched="$matched $p"
      else
        unknown="$unknown $p"
      fi
    done
    if [[ -n "${PROVEO_EGRESS_PROVIDER_DOMAINS:-}" ]]; then
      echo "acl provider_allow dstdomain ${PROVEO_EGRESS_PROVIDER_DOMAINS}"
      matched="$matched custom"
    fi
    # Visible write methods (POST/PUT/...) may go ONLY to the provider. Web reads
    # (docs/search/scraping) always stay allowed by the base policy below. Writes
    # to other hosts are denied for cleartext HTTP and, under TLS interception,
    # for HTTPS too. Without interception (plain proxy mode) HTTPS methods are
    # invisible to Squid, so that denial does not extend to HTTPS.
    echo "http_access allow unsafe_methods provider_allow"
  } >"$file"

  if [[ -z "${matched// /}" ]]; then
    echo "❌ unknown egress provider(s):${unknown}; set PROVEO_EGRESS_PROVIDER_DOMAINS to pin custom endpoints" >&2
    return 1
  fi
  [[ -n "${unknown// /}" ]] && echo "⚠️  ignoring unknown provider(s):${unknown}" >&2
  if [[ "${PROVEO_EGRESS_MODE:-}" == "inspected-firewall" ]]; then
    echo "🔒 Provider writes pinned to:${matched} — HTTPS is decrypted, so writes to other hosts are blocked (web reads stay open)" >&2
  else
    echo "🔒 Provider allowlist set for:${matched} (web reads stay open)" >&2
    echo "⚠️  proxy mode does NOT inspect HTTPS: writes/exfiltration over HTTPS to non-provider hosts are NOT blocked. Use --egress-mode inspected-firewall for enforced write-pinning." >&2
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
  # set, else auto-detected from the API keys present. The detected credential is
  # the intent — no extra flag required.
  PROVEO_EGRESS_PROVIDER_RESOLVED="${PROVEO_EGRESS_PROVIDER:-}"
  if [[ -z "$PROVEO_EGRESS_PROVIDER_RESOLVED" || "$PROVEO_EGRESS_PROVIDER_RESOLVED" == none ]]; then
    PROVEO_EGRESS_PROVIDER_RESOLVED="$(proveo_egress_detect_providers)"
  fi

  # A pinned provider is enforced by Squid, which only exists in proxy/inspected
  # modes. An EXPLICIT provider in open mode is a misconfig (nothing enforces the
  # allowlist) — refuse rather than imply containment. Auto-detection stays quiet
  # in open mode (no proxy to apply it to).
  if [[ -n "${PROVEO_EGRESS_PROVIDER:-}" && "${PROVEO_EGRESS_PROVIDER}" != "none" && "$mode" == "open" ]]; then
    echo "❌ PROVEO_EGRESS_PROVIDER requires --egress-mode proxy or inspected-firewall (open has no enforcement proxy)" >&2
    return 1
  fi

  # Preflight all sidecar images up front so a missing/unbuilt image fails fast
  # with an actionable message instead of half-building the topology.
  if ! proveo_egress_ensure_images "$mode" "$local_model"; then
    echo "❌ egress preflight failed: required image(s) not ready" >&2
    return 1
  fi

  case "$mode" in
    open)
      if [[ -n "$local_model" ]]; then
        # Name-based DNS is needed to reach the Ollama sidecar, which the default
        # bridge lacks. Use a user-defined bridge (still internet-capable) so the
        # agent keeps open egress and can resolve the sidecar by alias.
        agent_network="${PROVEO_EGRESS_SESSION_ID}-${safe_agent}-open-net"
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
    proxy|inspected-firewall)
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
    proveo_egress_start_mitm "$agent_network" "$enforce_network"
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

  if [[ "${PROVEO_KEEP_EGRESS:-0}" =~ ^(1|true|yes|on)$ ]]; then
    echo "🔎 Keeping egress sidecars/networks for session: $PROVEO_EGRESS_SESSION_ID"
    return 0
  fi

  # `+`-guard both loops: on bash < 4.4 (macOS ships 3.2) expanding an empty
  # array under `set -u` raises "unbound variable", which fires in open mode
  # where nothing was ever registered for cleanup.
  local item
  for item in ${PROVEO_EGRESS_CLEANUP_CONTAINERS[@]+"${PROVEO_EGRESS_CLEANUP_CONTAINERS[@]}"}; do
    docker rm -f "$item" >/dev/null 2>&1 || true
  done
  for item in ${PROVEO_EGRESS_CLEANUP_NETWORKS[@]+"${PROVEO_EGRESS_CLEANUP_NETWORKS[@]}"}; do
    docker network rm "$item" >/dev/null 2>&1 || true
  done
}
