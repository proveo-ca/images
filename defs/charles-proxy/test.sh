#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${PROVEO_CHARLES_PROXY_IMAGE:-proveo/charles-proxy:latest}"

docker run --rm --entrypoint /bin/bash "$IMAGE_NAME" -lc 'charles -help >/dev/null'
