#!/usr/bin/env bash
# Ensure proveo/base is available before building a harness image FROM it:
# present → done; else pull (mise deploy publishes it to Docker Hub); else
# build from this checkout. Called by each harness def's build.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${PROVEO_BASE_IMAGE:-proveo/base:latest}"

docker image inspect "$IMAGE" >/dev/null 2>&1 && exit 0
echo "📥 base image missing — pulling $IMAGE" >&2
docker pull "$IMAGE" >/dev/null 2>&1 && exit 0
echo "🔨 pull failed — building $IMAGE from source" >&2
exec "$SCRIPT_DIR/build.sh" --image "$IMAGE"
