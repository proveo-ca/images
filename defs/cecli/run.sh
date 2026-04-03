#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${CECLI_IMAGE:-proveo/cecli:node}"
INPUT_DIR="${CECLI_INPUT_DIR:-$(pwd)}"
OUTPUT_DIR="${CECLI_OUTPUT_DIR:-$(pwd)/reports}"
INSTALL_NODE_DEPS="${CECLI_INSTALL_NODE_DEPS:-0}"
READ_ONLY=0
CECLI_ARGS=()

usage() {
  echo "Usage: $0 [options] [cecli args...]"
  echo ""
  echo "Runs Cecli in Docker with workspace and output volume mounts."
  echo ""
  echo "Options:"
  echo "  --input-dir PATH       Workspace directory to mount at /app. Defaults to current directory."
  echo "  --output-dir PATH      Output directory to mount at /app/output. Defaults to ./reports."
  echo "  --image IMAGE          Docker image to run. Defaults to proveo/cecli:node."
  echo "  --python               Use proveo/cecli:python."
  echo "  --node                 Use proveo/cecli:node."
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
      IMAGE_NAME="proveo/cecli:node"
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

mkdir -p "$OUTPUT_DIR"

if [[ "$READ_ONLY" = "1" ]]; then
  APP_MOUNT_MODE="ro"
  CECLI_HOME_VALUE="${CECLI_HOME:-/tmp/.cecli}"
else
  APP_MOUNT_MODE="rw"
  CECLI_HOME_VALUE="${CECLI_HOME:-/app/.cecli}"
fi

echo "🚀 Starting Cecli..."
echo "Image:              $IMAGE_NAME"
echo "Input directory:    $INPUT_DIR"
echo "Output directory:   $OUTPUT_DIR"
echo "App mount mode:     $APP_MOUNT_MODE"
echo "CECLI_HOME:         $CECLI_HOME_VALUE"

docker run -it --rm \
  -e "LOCAL_UID=$(id -u)" \
  -e "LOCAL_GID=$(id -g)" \
  -e "CECLI_HOME=$CECLI_HOME_VALUE" \
  -e "CECLI_INSTALL_NODE_DEPS=$INSTALL_NODE_DEPS" \
  -v "$INPUT_DIR:/app:$APP_MOUNT_MODE" \
  -v "$OUTPUT_DIR:/app/output:rw" \
  -w /app \
  "$IMAGE_NAME" \
  "${CECLI_ARGS[@]}"
