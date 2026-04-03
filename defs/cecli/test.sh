#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${PROVEO_CECLI_IMAGE:-proveo/cecli:latest}"

docker run --rm "$IMAGE_NAME" bash -lc 'python --version && cecli --version'
