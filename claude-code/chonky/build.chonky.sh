#!/bin/bash

# Claude Security Container - Build and Run Script (Chonky Version)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NO_CACHE=""
if [[ "${1:-}" == "--no-cache" ]]; then
    NO_CACHE="--no-cache"
fi

echo "🔨 Building Claude Code Container (Chonky)..."
echo "📄 Using configuration: claude-config.chonky.json"

docker build ${NO_CACHE} -f "$SCRIPT_DIR/Dockerfile.chonky" -t claude-code-container-chonky "$SCRIPT_DIR"

echo "✅ Container built successfully!"
echo "📋 Usage examples:"
echo ""
echo "1. Interactive shell:"
echo "   ./run_claude.chonky.sh"
echo ""
echo "Container is ready! Use the scripts above to get started."
