#!/usr/bin/env bash
# SPEC: _spec/defs/claudecode/claudecode-topology.puml, _spec/defs/claudecode/claudecode-egress-topology.puml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/egress.sh
source "$DEFS_DIR/lib/egress.sh"
# shellcheck source=../lib/git-identity.sh
source "$DEFS_DIR/lib/git-identity.sh"
trap proveo_egress_cleanup EXIT

VARIANT="mcp"
IMAGE=""
EGRESS_MODE="firewall"
INPUT_DIR="$(pwd)"
OUTPUT_DIR="$(pwd)/reports"
DATA_DIR=""
SHELL_MODE=0
RUNTIME_ARGS=()

usage() {
  cat <<'EOF'
Usage:
  ./run.sh [--variant mcp|solo] [--image <image>] [--egress-mode <mode>] [options] [claude args...]

Runs the claudecode harness. The default variant is mcp.

Network Security Levels (Egress Modes):
  broker
      No proxy enforcement. The container uses the default Docker bridge
      network with direct internet access. Suitable for local development
      where no network isolation is required.

  proxy
      HTTP/HTTPS traffic is routed through a Squid enforcement proxy.
      Non-web protocols (SSH, database connections, etc.) are blocked by
      Docker network topology. The agent container cannot bypass the proxy.
      NOTE: without TLS interception Squid sees only "CONNECT host:443" for
      HTTPS, so it enforces destination host/port but NOT the request method.
      Writes/exfiltration over HTTPS to arbitrary hosts are therefore NOT
      blocked in this mode — use firewall for enforced write-pinning.

  firewall (default; recommended for production/auditing)
      HTTP/HTTPS traffic is first routed through proveo-egress (TLS MITM +
      credential broker) that decrypts and records each request
      (method/path/host), then through Squid for enforcement. Non-web
      protocols are blocked. This provides complete, decrypted audit trails
      of all outbound web requests.

Options:
  --input-dir PATH     Directory to mount as input (default: current directory)
  --output-dir PATH    Directory to mount as output (default: ./reports)
  --data-dir PATH      Optional data directory to mount read-only
  --local-model NAME   Assign a local Ollama model (e.g. gemma4). Starts an
                       Ollama sidecar on the agent network serving the host's
                       pulled models and points the harness model env at it.
                       Model calls bypass the egress proxy (NO_PROXY); all other
                       egress stays policed. Also honored via PROVEO_LOCAL_MODEL.
  --shell              Open bash in the container instead of launching Claude

Provider egress allowlist (proxy / firewall modes):
  The provider is auto-detected from whichever API key is present (current env
  or the project .env) — ANTHROPIC_API_KEY→anthropic, OPENAI_API_KEY→openai,
  GMI_API_KEY→gmi, AWS creds→bedrock, etc. Inference writes are then pinned to
  that provider's endpoint; web reads (docs/search/scraping) stay open. No flag
  needed — the key you already have is the intent. (Custom/self-hosted
  endpoints, if ever needed: PROVEO_EGRESS_PROVIDER_DOMAINS=".host".)
  IMPORTANT: write-pinning to "any other host is denied" is fully enforced only
  in firewall mode (TLS is decrypted). In proxy mode the pin applies
  to cleartext HTTP only; HTTPS writes to non-provider hosts are not blocked.

Examples:
  # Default (firewall mode: full inspection + enforcement, provider auto-detected)
  proveo run claudecode

  # Enforced proxy; egress auto-pinned to the provider of your present API key
  proveo run claudecode --egress-mode proxy

  # No egress enforcement (development only)
  proveo run claudecode --egress-mode broker
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --variant)
      [[ $# -ge 2 ]] || { echo "--variant requires a value" >&2; exit 1; }
      VARIANT="$2"
      shift 2
      ;;
    --image)
      [[ $# -ge 2 ]] || { echo "--image requires a value" >&2; exit 1; }
      IMAGE="$2"
      shift 2
      ;;
    --egress-mode)
      [[ $# -ge 2 ]] || { echo "--egress-mode requires a value" >&2; exit 1; }
      case "$2" in
        broker|proxy|firewall)
          EGRESS_MODE="$2"
          ;;
        *)
          echo "Invalid egress-mode: $2" >&2
          exit 1
          ;;
      esac
      shift 2
      ;;
    --input-dir)
      [[ $# -ge 2 ]] || { echo "--input-dir requires a value" >&2; exit 1; }
      INPUT_DIR="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || { echo "--output-dir requires a value" >&2; exit 1; }
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --data-dir)
      [[ $# -ge 2 ]] || { echo "--data-dir requires a value" >&2; exit 1; }
      DATA_DIR="$2"
      shift 2
      ;;
    --local-model)
      [[ $# -ge 2 ]] || { echo "--local-model requires a value" >&2; exit 1; }
      PROVEO_LOCAL_MODEL="$2"
      shift 2
      ;;
    --shell)
      SHELL_MODE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      RUNTIME_ARGS+=("$@")
      break
      ;;
    *)
      RUNTIME_ARGS+=("$1")
      shift
      ;;
  esac
done

case "$VARIANT" in
  mcp)
    IMAGE="${IMAGE:-${PROVEO_CLAUDECODE_IMAGE:-proveo/claudecode:latest}}"
    ;;
  solo)
    IMAGE="${IMAGE:-${PROVEO_CLAUDECODE_SOLO_IMAGE:-proveo/claudecode-solo:latest}}"
    ;;
  *)
    echo "Unknown claudecode variant: $VARIANT" >&2
    usage
    exit 1
    ;;
esac

if [[ ! -d "$INPUT_DIR" ]]; then
  echo "❌ Error: Input directory '$INPUT_DIR' does not exist" >&2
  exit 1
fi

if [[ -n "$DATA_DIR" && ! -d "$DATA_DIR" ]]; then
  echo "❌ Error: Data directory '$DATA_DIR' does not exist" >&2
  exit 1
fi

if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
  echo "⚠️  Warning: CLAUDE_CODE_OAUTH_TOKEN not set. Claude Code may not work properly."
  echo "   Set it with: export CLAUDE_CODE_OAUTH_TOKEN='your-oauth-token'"
  echo ""
fi

mkdir -p "$OUTPUT_DIR"

DOCKER_ARGS=(
  "run" "-it" "--rm"
  # Run as the caller's host UID/GID (never root) so files written to mounts
  # come back owned by the developer; the cap-drop hardening stays intact.
  "--user" "$(id -u):$(id -g)"
  "--cap-drop=ALL"
  "--security-opt=no-new-privileges:true"
  "--tmpfs" "/tmp:noexec,nosuid,size=100m"
  "--tmpfs" "/workspace/temp:noexec,nosuid,size=2g"
  "--pids-limit=512"
  "-v" "${INPUT_DIR}:/workspace/input:ro"
  "-v" "${OUTPUT_DIR}:/workspace/output:rw"
)

# Pass the raw token to the agent ONLY in broker mode. In proxy/broker the
# credential is withheld from the agent (firewall mode injects at the proxy).
if [[ "$EGRESS_MODE" == "broker" ]]; then
  DOCKER_ARGS+=("-e" "CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN:-}")
fi

# Forward the developer's git identity (host git config or GIT_* env) so the
# agent's commits are attributed to them; see defs/lib/git-identity.sh.
proveo_git_identity_env_args
DOCKER_ARGS+=(${PROVEO_GIT_IDENTITY_ARGS[@]+"${PROVEO_GIT_IDENTITY_ARGS[@]}"})

if [[ "$SHELL_MODE" == "1" ]]; then
  DOCKER_ARGS+=("--entrypoint" "bash")
fi

# Egress artifacts — Squid access logs, mitmproxy flow captures, and the
# mitmproxy CA *private key* — are audit evidence and secrets. They MUST live
# outside every path bind-mounted into the agent (input is RO, output is RW), or
# the sandboxed agent could read the CA key or tamper with its own audit trail.
# Keep them in a host-side state dir; override the base with PROVEO_EGRESS_ROOT.
EGRESS_STATE_ROOT="${PROVEO_EGRESS_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/proveo}"
if ! proveo_egress_prepare "$EGRESS_MODE" "claudecode-$VARIANT" "$EGRESS_STATE_ROOT"; then
  echo "❌ egress preflight failed; aborting before launch" >&2
  exit 1
fi
proveo_egress_append_agent_args DOCKER_ARGS

if [[ -n "$DATA_DIR" ]]; then
  DOCKER_ARGS+=("-v" "${DATA_DIR}:/workspace/data:ro")
  echo "📚 Using reference data from: $DATA_DIR"
fi

if [[ -d "$INPUT_DIR/.claude" ]]; then
  DOCKER_ARGS+=("-v" "${INPUT_DIR}/.claude:/workspace/.claude:ro")
  echo "🧩 Using project Claude config: $INPUT_DIR/.claude"
elif [[ -d "${HOME:-}/.claude" ]]; then
  # The host ~/.claude holds credentials, conversation history, and MCP configs.
  # Do NOT expose it to the sandboxed agent by default: an autonomous agent
  # running --dangerously-skip-permissions could read and (given open/proxy
  # egress) exfiltrate it. Opt in explicitly to inherit your personal config.
  if [[ "${PROVEO_MOUNT_HOME_CLAUDE:-0}" =~ ^(1|true|yes|on)$ ]]; then
    DOCKER_ARGS+=("-v" "${HOME}/.claude:/home/claude/.claude:ro")
    echo "🧩 Using home Claude config: ${HOME}/.claude (PROVEO_MOUNT_HOME_CLAUDE)"
  else
    echo "🔒 Not mounting host ~/.claude into the sandbox (set PROVEO_MOUNT_HOME_CLAUDE=1 to opt in)"
  fi
fi

if [[ "$SHELL_MODE" == "1" ]]; then
  echo "🐚 Starting Claude Code debug shell..."
else
  echo "🚀 Starting Claude Code in interactive mode..."
fi
echo "📦 Variant: $VARIANT"
echo "📁 Input: $INPUT_DIR"
echo "📊 Output: $OUTPUT_DIR"
if [[ ${#RUNTIME_ARGS[@]} -gt 0 ]]; then
  echo "🔧 Runtime options: ${RUNTIME_ARGS[*]}"
fi
echo ""

docker "${DOCKER_ARGS[@]}" "$IMAGE" "${RUNTIME_ARGS[@]}"
