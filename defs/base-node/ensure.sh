#!/usr/bin/env bash
# Ensure proveo/base-node is available before building a Node harness FROM it.
# Its build.sh chains defs/base/ensure.sh (the parent) first, so a clean machine
# builds base → base-node → harness in order.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${PROVEO_BASE_NODE_IMAGE:-proveo/base-node:latest}"

# Floor: the proveo/base floor plus a working Node + pnpm.
node_floor() {
  docker run --rm --entrypoint sh "$IMAGE" -c '
    command -v git >/dev/null \
      && command -v node >/dev/null \
      && command -v pnpm >/dev/null \
      && test -x /usr/local/bin/proveo-entrypoint
  ' >/dev/null 2>&1
}

if docker image inspect "$IMAGE" >/dev/null 2>&1; then
  if node_floor; then
    exit 0
  fi
  echo "⚠️  $IMAGE present but missing the node floor — rebuilding" >&2
  exec "$SCRIPT_DIR/build.sh" --image "$IMAGE"
fi

echo "📥 base-node image missing — pulling $IMAGE" >&2
if docker pull "$IMAGE" >/dev/null 2>&1 && node_floor; then
  exit 0
fi
echo "🔨 pull failed or image lacks the node floor — building $IMAGE from source" >&2
exec "$SCRIPT_DIR/build.sh" --image "$IMAGE"
