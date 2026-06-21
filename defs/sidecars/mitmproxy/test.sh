#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${PROVEO_MITMPROXY_IMAGE:-proveo/mitmproxy:latest}"

docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -lc '
  set -e
  mitmdump --version >/dev/null
  test -f /addons/ndjson_dump.py
  test -f /entrypoint.sh
'
