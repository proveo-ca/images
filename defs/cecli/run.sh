#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${CECLI_IMAGE:-proveo/cecli-node:latest}"
INPUT_DIR="${CECLI_INPUT_DIR:-$(pwd)}"
OUTPUT_DIR="${CECLI_OUTPUT_DIR:-$(pwd)/reports}"
REPO_ROOT=""
INSTALL_NODE_DEPS="${CECLI_INSTALL_NODE_DEPS:-0}"
READ_ONLY=0
CECLI_ARGS=()

usage() {
  echo "Usage: $0 [options] [cecli args...]"
  echo ""
  echo "Runs Cecli in Docker with workspace and output volume mounts. If the input"
  echo "directory is inside a git repository, the wrapper preserves the monorepo path"
  echo "under /app and mounts root .git for repo-aware tools."
  echo ""
  echo "Options:"
  echo "  --input-dir PATH       Workspace directory to mount at /app. Defaults to current directory."
  echo "  --output-dir PATH      Output directory to mount at /app/output. Defaults to ./reports."
  echo "  --repo-root PATH       Repository root for monorepo-aware mounts. Auto-detected when possible."
  echo "  --image IMAGE          Docker image to run. Defaults to proveo/cecli-node:latest."
  echo "  --python               Use proveo/cecli:python."
  echo "  --node                 Use proveo/cecli-node:latest."
  echo "  --read-only            Mount input directory read-only and store CECLI state in /tmp/.cecli."
  echo "  --help, -h             Show this help."
  echo ""
  echo "Environment:"
  echo "  CECLI_IMAGE            Override the Docker image."
  echo "  CECLI_INPUT_DIR        Override the input directory."
  echo "  CECLI_OUTPUT_DIR       Override the output directory."
  echo "  CECLI_INSTALL_NODE_DEPS=1"
  echo "                         Install Node dependencies when package.json is present."
}

require_value() {
  local option="$1"
  local value="${2:-}"

  if [[ -z "$value" ]]; then
    echo "❌ Missing value for $option" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --input-dir)
      require_value "$1" "${2:-}"
      INPUT_DIR="$2"
      shift 2
      ;;
    --output-dir)
      require_value "$1" "${2:-}"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --repo-root)
      require_value "$1" "${2:-}"
      REPO_ROOT="$(cd "$2" && pwd)"
      shift 2
      ;;
    --image)
      require_value "$1" "${2:-}"
      IMAGE_NAME="$2"
      shift 2
      ;;
    --python)
      IMAGE_NAME="proveo/cecli:python"
      shift
      ;;
    --node)
      IMAGE_NAME="proveo/cecli-node:latest"
      shift
      ;;
    --read-only)
      READ_ONLY=1
      shift
      ;;
    --)
      shift
      CECLI_ARGS+=("$@")
      break
      ;;
    *)
      CECLI_ARGS+=("$1")
      shift
      ;;
  esac
done

INPUT_DIR="$(cd "$INPUT_DIR" && pwd)"
OUTPUT_DIR="$(mkdir -p "$OUTPUT_DIR" && cd "$OUTPUT_DIR" && pwd)"

if [[ -z "$REPO_ROOT" ]] && git -C "$INPUT_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$INPUT_DIR" rev-parse --show-toplevel)"
fi

if [[ "$READ_ONLY" = "1" ]]; then
  APP_MOUNT_MODE="ro"
  CECLI_HOME_VALUE="${CECLI_HOME:-/tmp/.cecli}"
else
  APP_MOUNT_MODE="rw"
  CECLI_HOME_VALUE="${CECLI_HOME:-/app/.cecli}"
fi

DOCKER_ARGS=(
  "run" "-it" "--rm"
  "-e" "LOCAL_UID=$(id -u)"
  "-e" "LOCAL_GID=$(id -g)"
  "-e" "CECLI_HOME=$CECLI_HOME_VALUE"
  "-e" "CECLI_INSTALL_NODE_DEPS=$INSTALL_NODE_DEPS"
)

if [[ -n "$REPO_ROOT" && "$INPUT_DIR" == "$REPO_ROOT" ]]; then
  DOCKER_ARGS+=(--name "$(basename "$REPO_ROOT")-cecli")
  DOCKER_ARGS+=(-v "$REPO_ROOT:/app:$APP_MOUNT_MODE" -w /app)
elif [[ -n "$REPO_ROOT" && "$INPUT_DIR" == "$REPO_ROOT/"* ]]; then
  RELATIVE_SCOPE="${INPUT_DIR#$REPO_ROOT/}"
  DOCKER_ARGS+=(--name "$(basename "$REPO_ROOT")-${RELATIVE_SCOPE//\//-}-cecli")
  DOCKER_ARGS+=(-v "$INPUT_DIR:/app/$RELATIVE_SCOPE:$APP_MOUNT_MODE" -v "$REPO_ROOT/.git:/app/.git:ro" -w /app)
  for root_file in AGENTS.md CONVENTIONS.md CLAUDE.md .cecli.config.yml .cecli.config.yaml .cecli.conf.yml .cecli.conf.yaml .cecliignore package.json pnpm-workspace.yaml pnpm-lock.yaml package-lock.json yarn.lock turbo.json nx.json; do
    if [[ -e "$REPO_ROOT/$root_file" && ! -e "$INPUT_DIR/$root_file" ]]; then
      DOCKER_ARGS+=(-v "$REPO_ROOT/$root_file:/app/$root_file:ro")
    fi
  done
  if [[ -d "$REPO_ROOT/.cecli" && ! -e "$INPUT_DIR/.cecli" ]]; then
    DOCKER_ARGS+=(-v "$REPO_ROOT/.cecli:/app/.cecli:$APP_MOUNT_MODE")
  fi
  if [[ -f "$INPUT_DIR/.env" ]]; then
    DOCKER_ARGS+=(-v "$INPUT_DIR/.env:/app/.env:ro")
  elif [[ -f "$REPO_ROOT/.env" ]]; then
    DOCKER_ARGS+=(-v "$REPO_ROOT/.env:/app/.env:ro")
  fi
  for scoped_file in .cecli.config.yml .cecli.config.yaml .cecli.conf.yml .cecli.conf.yaml .cecliignore; do
    if [[ -e "$INPUT_DIR/$scoped_file" && ! -e "$REPO_ROOT/$scoped_file" ]]; then
      DOCKER_ARGS+=(-v "$INPUT_DIR/$scoped_file:/app/$scoped_file:ro")
    fi
  done
else
  DOCKER_ARGS+=(--name "$(basename "$INPUT_DIR")-cecli")
  DOCKER_ARGS+=(-v "$INPUT_DIR:/app:$APP_MOUNT_MODE" -w /app)
fi

DOCKER_ARGS+=(-v "$OUTPUT_DIR:/app/output:rw")

echo "🚀 Starting Cecli..."
echo "Image:              $IMAGE_NAME"
echo "Input directory:    $INPUT_DIR"
echo "Output directory:   $OUTPUT_DIR"
if [[ -n "$REPO_ROOT" ]]; then
  echo "Repository root:    $REPO_ROOT"
fi
echo "App mount mode:     $APP_MOUNT_MODE"
echo "CECLI_HOME:         $CECLI_HOME_VALUE"

docker "${DOCKER_ARGS[@]}" "$IMAGE_NAME" "${CECLI_ARGS[@]}"
