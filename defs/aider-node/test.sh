#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${PROVEO_AIDER_NODE_IMAGE:-proveo/aider-node:latest}"

docker run --rm "$IMAGE_NAME" bash -lc 'node --version && npm -v && timeout 10s pnpm -v && aider --version'
