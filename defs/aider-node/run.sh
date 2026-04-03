#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${PROVEO_AIDER_NODE_IMAGE:-proveo/aider-node:latest}"
INPUT_DIR="$PWD"
REPO_ROOT=""
ENTRYPOINT=""
AIDER_ARGS=()

usage() {
  cat <<'EOF'
Usage:
  ./run.sh [--image <image>] [--input-dir <path>] [--repo-root <path>] [--entrypoint <cmd>] [-- <aider args...>]

Runs the aider-node harness. If --repo-root is supplied and --input-dir is
inside that repo, the script preserves the monorepo path under /app and mounts
.repo-root/.git for repository-map support.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      if [[ $# -lt 2 ]]; then
        echo "--image requires a value" >&2
        exit 1
      fi
      IMAGE_NAME="$2"
      shift 2
      ;;
    --input-dir)
      if [[ $# -lt 2 ]]; then
        echo "--input-dir requires a value" >&2
        exit 1
      fi
      INPUT_DIR="$(cd "$2" && pwd)"
      shift 2
      ;;
    --repo-root)
      if [[ $# -lt 2 ]]; then
        echo "--repo-root requires a value" >&2
        exit 1
      fi
      REPO_ROOT="$(cd "$2" && pwd)"
      shift 2
      ;;
    --entrypoint)
      if [[ $# -lt 2 ]]; then
        echo "--entrypoint requires a value" >&2
        exit 1
      fi
      ENTRYPOINT="$2"
      shift 2
      ;;
    --)
      shift
      AIDER_ARGS+=("$@")
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      AIDER_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  if git -C "$INPUT_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO_ROOT="$(git -C "$INPUT_DIR" rev-parse --show-toplevel)"
  fi
fi

DOCKER_ARGS=(run -it --rm)

if [[ -n "$ENTRYPOINT" ]]; then
  DOCKER_ARGS+=(--entrypoint "$ENTRYPOINT")
fi

if [[ -n "$REPO_ROOT" && "$INPUT_DIR" == "$REPO_ROOT" ]]; then
  DOCKER_ARGS+=(--name "$(basename "$REPO_ROOT")")
  DOCKER_ARGS+=(-v "$REPO_ROOT:/app" -w /app)
elif [[ -n "$REPO_ROOT" && "$INPUT_DIR" == "$REPO_ROOT/"* ]]; then
  RELATIVE_SCOPE="${INPUT_DIR#$REPO_ROOT/}"
  DOCKER_ARGS+=(--name "$(basename "$REPO_ROOT")-${RELATIVE_SCOPE//\//-}")
  DOCKER_ARGS+=(-v "$INPUT_DIR:/app/$RELATIVE_SCOPE" -v "$REPO_ROOT/.git:/app/.git" -w /app)
  if [[ -f "$INPUT_DIR/.aiderignore" ]]; then
    DOCKER_ARGS+=(-v "$INPUT_DIR/.aiderignore:/app/.aiderignore")
  fi
else
  DOCKER_ARGS+=(--name "$(basename "$INPUT_DIR")")
  DOCKER_ARGS+=(-v "$INPUT_DIR:/app" -w /app)
fi

DOCKER_ARGS+=("$IMAGE_NAME")
DOCKER_ARGS+=("${AIDER_ARGS[@]}")

docker "${DOCKER_ARGS[@]}"
