#!/usr/bin/env bash
# SPEC: _spec/defs/cursor/cursor-topology.puml, _spec/defs/cursor/cursor.paradigm.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/egress.sh
source "$DEFS_DIR/lib/egress.sh"
# shellcheck source=../lib/git-identity.sh
source "$DEFS_DIR/lib/git-identity.sh"
trap proveo_egress_cleanup EXIT

IMAGE_NAME="${PROVEO_CURSOR_IMAGE:-proveo/cursor:latest}"
EGRESS_MODE="open"
INPUT_DIR="$PWD"
REPO_ROOT=""
SHELL_MODE=0
CURSOR_ARGS=()

usage() {
  cat <<'EOF'
Usage:
  ./run.sh [--image <image>] [--input-dir <path>] [--repo-root <path>]
           [--egress-mode <mode>] [--shell] [-- <agent args...>]

Runs the cursor harness (Cursor CLI, `agent`). If the input directory is inside
a git repository, the wrapper preserves the monorepo path under /app and mounts
root .git for repo-aware tools.

Network Security Levels (Egress Modes):
  open                No proxy enforcement (default Docker bridge).
  proxy               HTTP/HTTPS via Squid enforcement proxy; non-web protocols
                      blocked by Docker network topology.
  firewall  mitmproxy (TLS-decrypting recorder) → Squid → internet;
                      complete decrypted audit trail of outbound web requests.

Options:
  --shell             Open bash in the container instead of launching the agent

Cursor-specific notes:
  ALL inference transits the Cursor backend (api5.cursor.sh / api2.cursor.sh);
  there is no custom base-URL or local-model path. In proxy/firewall
  modes, inference writes are pinned to the Cursor domains (CURSOR_API_KEY is
  the detected intent). --local-model / PROVEO_LOCAL_MODEL do not apply here.

Examples:
  # Interactive TUI in the current repo
  ./run.sh

  # Headless autonomous run, fully audited egress
  CURSOR_API_KEY=... ./run.sh --egress-mode firewall -- \
    -p "Fix the failing tests" --output-format stream-json
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      [[ $# -ge 2 ]] || { echo "--image requires a value" >&2; exit 1; }
      IMAGE_NAME="$2"
      shift 2
      ;;
    --input-dir)
      [[ $# -ge 2 ]] || { echo "--input-dir requires a value" >&2; exit 1; }
      INPUT_DIR="$(cd "$2" && pwd)"
      shift 2
      ;;
    --repo-root)
      [[ $# -ge 2 ]] || { echo "--repo-root requires a value" >&2; exit 1; }
      REPO_ROOT="$(cd "$2" && pwd)"
      shift 2
      ;;
    --egress-mode)
      [[ $# -ge 2 ]] || { echo "--egress-mode requires a value" >&2; exit 1; }
      case "$2" in
        open|proxy|firewall)
          EGRESS_MODE="$2"
          ;;
        *)
          echo "Invalid egress-mode: $2" >&2
          exit 1
          ;;
      esac
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
      CURSOR_ARGS+=("$@")
      break
      ;;
    *)
      CURSOR_ARGS+=("$1")
      shift
      ;;
  esac
done

# Cursor CLI cannot use a local model: inference is vendor-pinned to the Cursor
# backend. Fail fast instead of silently starting a useless Ollama sidecar.
if [[ -n "${PROVEO_LOCAL_MODEL:-}" ]]; then
  echo "❌ PROVEO_LOCAL_MODEL is set, but Cursor CLI has no local-model path;" >&2
  echo "   all inference transits the Cursor backend. Unset it or use claudecode." >&2
  exit 1
fi

if [[ -z "${CURSOR_API_KEY:-}" ]]; then
  echo "⚠️  Warning: CURSOR_API_KEY not set. Create one at cursor.com/dashboard,"
  echo "   or run 'agent login' inside the container (tokens live in ~/.cursor)."
  echo ""
fi

INPUT_DIR="$(cd "$INPUT_DIR" && pwd)"
if [[ -z "$REPO_ROOT" ]] && git -C "$INPUT_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$INPUT_DIR" rev-parse --show-toplevel)"
fi

DOCKER_ARGS=("run" "-it" "--rm")
# Run as the caller's host UID/GID (never root) so files written to the mounted
# workspace come back owned by the developer, for any uid — not just 1000.
DOCKER_ARGS+=("--user" "$(id -u):$(id -g)")
# Capability/privilege hardening baseline, matching the claudecode runner.
DOCKER_ARGS+=("--cap-drop=ALL" "--security-opt=no-new-privileges:true" "--pids-limit=100")
# Pass the raw key to the agent ONLY in open mode. In proxy/firewall the egress
# broker injects it at the proxy, so the agent process never sees the credential
# (it cannot then be exfiltrated by a compromised/prompt-injected agent).
if [[ "$EGRESS_MODE" == "open" ]]; then
  DOCKER_ARGS+=("-e" "CURSOR_API_KEY=${CURSOR_API_KEY:-}")
fi
# Forward the developer's git identity (host git config or GIT_* env) so the
# agent's commits are attributed to them; see defs/lib/git-identity.sh.
proveo_git_identity_env_args
DOCKER_ARGS+=(${PROVEO_GIT_IDENTITY_ARGS[@]+"${PROVEO_GIT_IDENTITY_ARGS[@]}"})

if [[ -n "$REPO_ROOT" && "$INPUT_DIR" == "$REPO_ROOT" ]]; then
  CONTAINER_NAME="$(basename "$REPO_ROOT")-cursor"
  DOCKER_ARGS+=(--name "$CONTAINER_NAME")
  DOCKER_ARGS+=(-v "$REPO_ROOT:/app" -w /app)
elif [[ -n "$REPO_ROOT" && "$INPUT_DIR" == "$REPO_ROOT/"* ]]; then
  RELATIVE_SCOPE="${INPUT_DIR#$REPO_ROOT/}"
  CONTAINER_NAME="$(basename "$REPO_ROOT")-${RELATIVE_SCOPE//\//-}-cursor"
  DOCKER_ARGS+=(--name "$CONTAINER_NAME")
  DOCKER_ARGS+=(-v "$INPUT_DIR:/app/$RELATIVE_SCOPE" -v "$REPO_ROOT/.git:/app/.git" -w /app)
  for root_file in AGENTS.md CONVENTIONS.md CLAUDE.md .cursorrules package.json pnpm-workspace.yaml pnpm-lock.yaml package-lock.json yarn.lock turbo.json nx.json; do
    if [[ -e "$REPO_ROOT/$root_file" && ! -e "$INPUT_DIR/$root_file" ]]; then
      DOCKER_ARGS+=(-v "$REPO_ROOT/$root_file:/app/$root_file:ro")
    fi
  done
  if [[ -d "$REPO_ROOT/.cursor" && ! -e "$INPUT_DIR/.cursor" ]]; then
    DOCKER_ARGS+=(-v "$REPO_ROOT/.cursor:/app/.cursor:ro")
  fi
  if [[ -f "$INPUT_DIR/.env" ]]; then
    DOCKER_ARGS+=(-v "$INPUT_DIR/.env:/app/.env:ro")
  elif [[ -f "$REPO_ROOT/.env" ]]; then
    DOCKER_ARGS+=(-v "$REPO_ROOT/.env:/app/.env:ro")
  fi
else
  CONTAINER_NAME="$(basename "$INPUT_DIR")-cursor"
  DOCKER_ARGS+=(--name "$CONTAINER_NAME")
  DOCKER_ARGS+=(-v "$INPUT_DIR:/app" -w /app)
fi

# The host ~/.cursor holds Cursor credentials and session history. Do NOT
# expose it to the sandboxed agent by default: an autonomous agent running
# --force could read and (given open/proxy egress) exfiltrate it. Opt in
# explicitly to inherit your personal config.
if [[ "${PROVEO_MOUNT_HOME_CURSOR:-0}" =~ ^(1|true|yes|on)$ && -d "${HOME:-}/.cursor" ]]; then
  DOCKER_ARGS+=(-v "${HOME}/.cursor:/home/cursor/.cursor:ro")
  echo "🧩 Using home Cursor config: ${HOME}/.cursor (PROVEO_MOUNT_HOME_CURSOR)"
fi

if [[ "$SHELL_MODE" == "1" ]]; then
  DOCKER_ARGS+=("--entrypoint" "bash")
fi

# Egress artifacts (Squid logs, mitmproxy flows, mitmproxy CA key) are audit
# evidence and secrets: keep them in a host-side state dir outside every path
# bind-mounted into the agent. Override the base with PROVEO_EGRESS_ROOT.
EGRESS_STATE_ROOT="${PROVEO_EGRESS_ROOT:-${XDG_STATE_HOME:-$HOME/.local/state}/proveo}"
if ! proveo_egress_prepare "$EGRESS_MODE" "cursor" "$EGRESS_STATE_ROOT"; then
  echo "❌ egress preflight failed; aborting before launch" >&2
  exit 1
fi
proveo_egress_append_agent_args DOCKER_ARGS

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

if [[ "$SHELL_MODE" == "1" ]]; then
  echo "🐚 Starting cursor debug shell..."
else
  echo "🚀 Starting Cursor CLI..."
fi
echo "📁 Input: $INPUT_DIR"

# Empty-array guard: bash 3.2 (macOS /bin/bash) treats "${arr[@]}" of an empty
# array as unbound under set -u.
docker "${DOCKER_ARGS[@]}" "$IMAGE_NAME" ${CURSOR_ARGS[@]+"${CURSOR_ARGS[@]}"}
