#!/bin/bash

# Claude Code Container - Build Script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NO_CACHE=""
if [[ "${1:-}" == "--no-cache" ]]; then
    NO_CACHE="--no-cache"
fi

echo "🔨 Building Claude Code Container..."
docker build ${NO_CACHE} -t claude-code-container -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"
echo "✅ Container built successfully!"
echo ""
echo "📋 Usage examples:"
echo "   ./run_claude.sh"
echo "   ./run_claude.sh --help"
