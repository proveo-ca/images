#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${PROVEO_MITMPROXY_IMAGE:-proveo/mitmproxy}"
NO_CACHE=""

usage() {
  cat <<'EOF'
Usage:
  ./build.sh [--tag <tag>] [--no-cache]

Builds the mitmproxy inspector harness image.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      if [[ $# -lt 2 ]]; then
        echo "--tag requires a value" >&2
        exit 1
      fi
      IMAGE_NAME="proveo/mitmproxy:$2"
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

docker build ${NO_CACHE:+$NO_CACHE} -t "$IMAGE_NAME" "$SCRIPT_DIR"
