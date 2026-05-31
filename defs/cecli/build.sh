#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-proveo/cecli}"

echo "Building $IMAGE_NAME:python..."
docker build -t "$IMAGE_NAME:python" -f "$SCRIPT_DIR/Dockerfile.python" "$SCRIPT_DIR"

echo "Building $IMAGE_NAME:node..."
docker build -t "$IMAGE_NAME:node" -f "$SCRIPT_DIR/Dockerfile.node" "$SCRIPT_DIR"

echo "Tagging $IMAGE_NAME:node as $IMAGE_NAME:latest..."
docker tag "$IMAGE_NAME:node" "$IMAGE_NAME:latest"

echo "Tagging $IMAGE_NAME:node as $IMAGE_NAME:local..."
docker tag "$IMAGE_NAME:node" "$IMAGE_NAME:local"

echo "✅ Built:"
echo "  $IMAGE_NAME:python"
echo "  $IMAGE_NAME:node"
echo "  $IMAGE_NAME:latest"
echo "  $IMAGE_NAME:local"
