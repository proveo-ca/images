#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${PROVEO_OPENCODE_IMAGE:-proveo/opencode:latest}"
INPUT_DIR="$PWD"
OPENCODE_ARGS=()

usage() {
  cat <<'EOF'
Usage:
  ./run.sh [--image <image>] [--input-dir <path>] [-- <opencode args...>]

Runs the opencode harness.
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

docker run -it --rm   --name "$(basename "$INPUT_DIR")-opencode"   -v "$INPUT_DIR:/app"   -w /app   "$IMAGE_NAME"   "${OPENCODE_ARGS[@]}"
