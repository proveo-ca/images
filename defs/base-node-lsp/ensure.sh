#!/usr/bin/env bash
# Ensure proveo/base-node-lsp is available before building an LSP harness FROM it.
# Its build.sh chains defs/base-node/ensure.sh (→ base) first, so a clean machine
# builds base → base-node → base-node-lsp → harness in order.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${PROVEO_BASE_NODE_LSP_IMAGE:-proveo/base-node-lsp:latest}"

# Floor: the base-node floor plus the shared language servers.
lsp_floor() {
  docker run --rm --entrypoint sh "$IMAGE" -c '
    command -v node >/dev/null \
      && command -v jq >/dev/null \
      && command -v typescript-language-server >/dev/null \
      && command -v pyright-langserver >/dev/null
  ' >/dev/null 2>&1
}

if docker image inspect "$IMAGE" >/dev/null 2>&1; then
  if lsp_floor; then
    exit 0
  fi
  echo "⚠️  $IMAGE present but missing the LSP floor — rebuilding" >&2
  exec "$SCRIPT_DIR/build.sh" --image "$IMAGE"
fi

echo "📥 base-node-lsp image missing — pulling $IMAGE" >&2
if docker pull "$IMAGE" >/dev/null 2>&1 && lsp_floor; then
  exit 0
fi
echo "🔨 pull failed or image lacks the LSP floor — building $IMAGE from source" >&2
exec "$SCRIPT_DIR/build.sh" --image "$IMAGE"
