#!/usr/bin/env bash
# Build the Go egress inspection proxy image. Build context is the repo root
# (the Go module); the Dockerfile lives here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

IMAGE="${PROVEO_EGRESS_PROXY_IMAGE:-proveo/egress-proxy:latest}"
TAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --image) IMAGE="$2"; shift 2 ;;
    -h|--help) echo "Usage: build.sh [--image NAME] [--tag TAG]"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
[[ -n "$TAG" ]] && IMAGE="${IMAGE%%:*}:$TAG"

echo "🔨 building $IMAGE (context: $REPO_ROOT)"
exec docker build \
  -f "$SCRIPT_DIR/Dockerfile" \
  -t "$IMAGE" \
  "$REPO_ROOT"
