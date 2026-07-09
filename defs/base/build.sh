#!/usr/bin/env bash
# Build the shared harness base image. Build context is the repo root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

IMAGE="${PROVEO_BASE_IMAGE:-proveo/base:latest}"
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

echo "🔨 building $IMAGE (context: $REPO_ROOT)"
exec docker build \
  ${NO_CACHE:+$NO_CACHE} \
  -f "$SCRIPT_DIR/Dockerfile" \
  -t "$IMAGE" \
  "$REPO_ROOT"
