#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${PROVEO_AIDER_NODE_IMAGE:-proveo/aider-node}"
NO_CACHE=""

usage() {
  cat <<'EOF'
Usage:
  ./build.sh [--tag <tag>] [--no-cache]

Builds the aider-node harness image.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      if [[ $# -lt 2 ]]; then
        echo "--tag requires a value" >&2
        exit 1
      fi
      IMAGE_NAME="proveo/aider-node:$2"
      shift 2
      ;;
    --no-cache)
      NO_CACHE="--no-cache"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown build option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# Copy shared library before building
cp -f "$SCRIPT_DIR/../../packages/lib/entrypoint-lib.sh" "$SCRIPT_DIR/"
trap 'rm -f "$SCRIPT_DIR/entrypoint-lib.sh"' EXIT

docker build ${NO_CACHE:+$NO_CACHE} -t "$IMAGE_NAME" -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR/../.."
