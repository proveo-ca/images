#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/git-identity.sh
source "$SCRIPT_DIR/../lib/git-identity.sh"

IMAGE_NAME="${PROVEO_OPENCODE_IMAGE:-proveo/opencode:latest}"
INPUT_DIR="$PWD"
REPO_ROOT=""
OPENCODE_ARGS=()

usage() {
  cat <<'EOF'
Usage:
  ./run.sh [--image <image>] [--input-dir <path>] [--repo-root <path>] [-- <opencode args...>]

Runs the opencode harness. If the input directory is inside a git repository,
the wrapper preserves the monorepo path under /app and mounts root .git for
repo-aware tools.
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
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      OPENCODE_ARGS+=("$@")
      break
      ;;
    *)
      OPENCODE_ARGS+=("$1")
      shift
      ;;
  esac
done

INPUT_DIR="$(cd "$INPUT_DIR" && pwd)"
if [[ -z "$REPO_ROOT" ]] && git -C "$INPUT_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$INPUT_DIR" rev-parse --show-toplevel)"
fi

DOCKER_ARGS=("run" "-it" "--rm")
# Run as the caller's host UID/GID (never root) so files written to the mounted
# workspace come back owned by the developer, for any uid — not just 1000.
DOCKER_ARGS+=("--user" "$(id -u):$(id -g)")
# Forward the developer's git identity (host git config or GIT_* env) so the
# agent's commits are attributed to them; see defs/lib/git-identity.sh.
proveo_git_identity_env_args
DOCKER_ARGS+=(${PROVEO_GIT_IDENTITY_ARGS[@]+"${PROVEO_GIT_IDENTITY_ARGS[@]}"})
if [[ -n "$REPO_ROOT" && "$INPUT_DIR" == "$REPO_ROOT" ]]; then
  CONTAINER_NAME="$(basename "$REPO_ROOT")-opencode"
  DOCKER_ARGS+=(--name "$CONTAINER_NAME")
  DOCKER_ARGS+=(-v "$REPO_ROOT:/app" -w /app)
elif [[ -n "$REPO_ROOT" && "$INPUT_DIR" == "$REPO_ROOT/"* ]]; then
  RELATIVE_SCOPE="${INPUT_DIR#$REPO_ROOT/}"
  CONTAINER_NAME="$(basename "$REPO_ROOT")-${RELATIVE_SCOPE//\//-}-opencode"
  DOCKER_ARGS+=(--name "$CONTAINER_NAME")
  DOCKER_ARGS+=(-v "$INPUT_DIR:/app/$RELATIVE_SCOPE" -v "$REPO_ROOT/.git:/app/.git" -w /app)
  for root_file in AGENTS.md CONVENTIONS.md CLAUDE.md opencode.json opencode.jsonc package.json pnpm-workspace.yaml pnpm-lock.yaml package-lock.json yarn.lock turbo.json nx.json; do
    if [[ -e "$REPO_ROOT/$root_file" && ! -e "$INPUT_DIR/$root_file" ]]; then
      DOCKER_ARGS+=(-v "$REPO_ROOT/$root_file:/app/$root_file:ro")
    fi
  done
  if [[ -d "$REPO_ROOT/.opencode" && ! -e "$INPUT_DIR/.opencode" ]]; then
    DOCKER_ARGS+=(-v "$REPO_ROOT/.opencode:/app/.opencode:ro")
  fi
  if [[ -f "$INPUT_DIR/.env" ]]; then
    DOCKER_ARGS+=(-v "$INPUT_DIR/.env:/app/.env:ro")
  elif [[ -f "$REPO_ROOT/.env" ]]; then
    DOCKER_ARGS+=(-v "$REPO_ROOT/.env:/app/.env:ro")
  fi
else
  CONTAINER_NAME="$(basename "$INPUT_DIR")-opencode"
  DOCKER_ARGS+=(--name "$CONTAINER_NAME")
  DOCKER_ARGS+=(-v "$INPUT_DIR:/app" -w /app)
fi

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

# Empty-array guard: bash 3.2 (macOS /bin/bash) treats "${arr[@]}" of an empty
# array as unbound under set -u.
docker "${DOCKER_ARGS[@]}" "$IMAGE_NAME" ${OPENCODE_ARGS[@]+"${OPENCODE_ARGS[@]}"}
