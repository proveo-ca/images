#!/usr/bin/env bash
# Ensure proveo/base is available before building a harness image FROM it:
# present with a usable floor → done; else pull (mise deploy publishes it to
# Docker Hub); else build from this checkout. Called by each harness def's
# build.sh (Node harnesses go through defs/base-node/ensure.sh, which chains
# here first).
#
# A local tag alone is not enough: a stale proveo/base:latest from a different
# lineage (e.g. the old Playwright-browser base) looks "present" but has the
# wrong floor, so harness builds would silently ship the wrong contents. The
# floor probe below is what makes `mise build <harness>` safe on any machine.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${PROVEO_BASE_IMAGE:-proveo/base:latest}"

# The minimal-floor contract: git + gh + the proveo-entrypoint binary. (No
# browsers/Node/Python — those moved out of the base.)
base_has_floor() {
  docker run --rm --entrypoint sh "$IMAGE" -c '
    command -v git >/dev/null \
      && command -v gh >/dev/null \
      && command -v jq >/dev/null \
      && test -x /usr/local/bin/proveo-entrypoint
  ' >/dev/null 2>&1
}

if docker image inspect "$IMAGE" >/dev/null 2>&1; then
  if base_has_floor; then
    exit 0
  fi
  echo "⚠️  $IMAGE is present but missing the proveo/base floor — rebuilding" >&2
  exec "$SCRIPT_DIR/build.sh" --image "$IMAGE"
fi

echo "📥 base image missing — pulling $IMAGE" >&2
if docker pull "$IMAGE" >/dev/null 2>&1 && base_has_floor; then
  exit 0
fi
echo "🔨 pull failed or image lacks the floor — building $IMAGE from source" >&2
exec "$SCRIPT_DIR/build.sh" --image "$IMAGE"
