#!/usr/bin/env bash
# Ensure proveo/base is available before building a harness image FROM it:
# present with a usable Playwright floor → done; else pull (mise deploy
# publishes it to Docker Hub); else build from this checkout. Called by each
# harness def's build.sh.
#
# A local tag alone is not enough: stale proveo/base:latest images from before
# the Playwright floor (or built without the MCR base) look "present" and then
# harness builds silently ship without libglib / Chromium.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${PROVEO_BASE_IMAGE:-proveo/base:latest}"

base_has_playwright_floor() {
  docker run --rm --entrypoint bash "$IMAGE" -c '
    command -v playwright >/dev/null \
      && test -n "${PLAYWRIGHT_BROWSERS_PATH:-}" \
      && test -d "$PLAYWRIGHT_BROWSERS_PATH" \
      && ls "$PLAYWRIGHT_BROWSERS_PATH" | grep -q chromium \
      && ldconfig -p 2>/dev/null | grep -q "libglib-2.0.so.0"
  ' >/dev/null 2>&1
}

if docker image inspect "$IMAGE" >/dev/null 2>&1; then
  if base_has_playwright_floor; then
    exit 0
  fi
  echo "⚠️  $IMAGE is present but missing the Playwright floor — rebuilding" >&2
  exec "$SCRIPT_DIR/build.sh" --image "$IMAGE"
fi

echo "📥 base image missing — pulling $IMAGE" >&2
if docker pull "$IMAGE" >/dev/null 2>&1 && base_has_playwright_floor; then
  exit 0
fi
echo "🔨 pull failed or image lacks Playwright floor — building $IMAGE from source" >&2
exec "$SCRIPT_DIR/build.sh" --image "$IMAGE"
