#!/usr/bin/env bash
# Build proveo/base-node-browser (proveo/base-node-lsp + Playwright + Chromium).
# Ensures proveo/base-node-lsp exists first (which chains base-node → base). The
# Dockerfile pulls nothing from the repo, so the build context is this dir.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IMAGE="${PROVEO_BASE_NODE_BROWSER_IMAGE:-proveo/base-node-browser:latest}"
TAG=""
NO_CACHE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --image) IMAGE="$2"; shift 2 ;;
    --no-cache) NO_CACHE="--no-cache"; shift ;;
    -h|--help) echo "Usage: build.sh [--image NAME] [--tag TAG] [--no-cache]"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
[[ -n "$TAG" ]] && IMAGE="${IMAGE%%:*}:$TAG"

"$SCRIPT_DIR/../base-node-lsp/ensure.sh"

echo "🔨 building $IMAGE (context: $SCRIPT_DIR)"
exec docker build \
  ${NO_CACHE:+$NO_CACHE} \
  -f "$SCRIPT_DIR/Dockerfile" \
  -t "$IMAGE" \
  "$SCRIPT_DIR"
