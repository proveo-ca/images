#!/usr/bin/env bash
# SPEC: _spec/defs/claudecode/claudecode-topology.puml, _spec/defs/claudecode/claudecode-egress-topology.puml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/egress.sh
source "$DEFS_DIR/lib/egress.sh"
trap proveo_egress_cleanup EXIT

VARIANT="mcp"
IMAGE=""
EGRESS_MODE="open"
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
  open
      No proxy enforcement. The container uses the default Docker bridge
      network with direct internet access. Suitable for local development
      where no network isolation is required.

  proxy
      HTTP/HTTPS traffic is routed through a Squid enforcement proxy.
      Non-web protocols (SSH, database connections, etc.) are blocked by
      Docker network topology. The agent container cannot bypass the proxy.

  inspected-firewall (recommended for production/auditing)
      HTTP/HTTPS traffic is first routed through a mitmproxy inspection proxy
      that decrypts and records each request (method/path/host), then through
      Squid for enforcement. Non-web protocols are blocked. This provides
      complete, decrypted audit trails of all outbound web requests.

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

Provider egress allowlist (proxy / inspected-firewall modes):
  The provider is auto-detected from whichever API key is present (current env
  or the project .env) — ANTHROPIC_API_KEY→anthropic, OPENAI_API_KEY→openai,
  GMI_API_KEY→gmi, AWS creds→bedrock, etc. Inference writes are then pinned to
  that provider's endpoint; web reads (docs/search/scraping) stay open and
  writes to any other host are denied. No flag needed — the key you already
  have is the intent. (Custom/self-hosted endpoints, if ever needed:
  PROVEO_EGRESS_PROVIDER_DOMAINS=".host".)

Examples:
  # Default (open mode)
  proveo run claudecode

  # Enforced proxy; egress auto-pinned to the provider of your present API key
  proveo run claudecode --egress-mode proxy

  # Full inspection + enforcement (provider still auto-detected)
  proveo run claudecode --egress-mode inspected-firewall
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
        open|proxy|inspected-firewall)
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
  "--cap-drop=ALL"
  "--security-opt=no-new-privileges:true"
  "--tmpfs" "/tmp:noexec,nosuid,size=100m"
  "--tmpfs" "/workspace/temp:noexec,nosuid,size=2g"
  "--pids-limit=100"
  "-v" "${INPUT_DIR}:/workspace/input:ro"
  "-v" "${OUTPUT_DIR}:/workspace/output:rw"
  "-e" "CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN:-}"
)

if [[ "$SHELL_MODE" == "1" ]]; then
  DOCKER_ARGS+=("--entrypoint" "bash")
fi

if ! proveo_egress_prepare "$EGRESS_MODE" "claudecode-$VARIANT" "$OUTPUT_DIR"; then
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
  DOCKER_ARGS+=("-v" "${HOME}/.claude:/home/claude/.claude:ro")
  echo "🧩 Using home Claude config: ${HOME}/.claude"
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
