#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-proveo/cecli}"
NODE_IMAGE_NAME="${NODE_IMAGE_NAME:-proveo/cecli-node}"

# Copy shared library before building
cp -f "$SCRIPT_DIR/../../packages/lib/entrypoint-lib.sh" "$SCRIPT_DIR/"
trap 'rm -f "$SCRIPT_DIR/entrypoint-lib.sh"' EXIT

echo "Building $IMAGE_NAME:python..."
docker build -t "$IMAGE_NAME:python" -f "$SCRIPT_DIR/Dockerfile.python" "$SCRIPT_DIR"

echo "Building $NODE_IMAGE_NAME:latest..."
docker build -t "$NODE_IMAGE_NAME:latest" -f "$SCRIPT_DIR/Dockerfile.node" "$SCRIPT_DIR"

echo "Tagging $NODE_IMAGE_NAME:latest as $IMAGE_NAME:latest..."
docker tag "$NODE_IMAGE_NAME:latest" "$IMAGE_NAME:latest"

echo "Tagging $NODE_IMAGE_NAME:latest as $IMAGE_NAME:local..."
docker tag "$NODE_IMAGE_NAME:latest" "$IMAGE_NAME:local"

echo "✅ Built:"
echo "  $IMAGE_NAME:python"
echo "  $NODE_IMAGE_NAME:latest"
echo "  $IMAGE_NAME:latest"
echo "  $IMAGE_NAME:local"
