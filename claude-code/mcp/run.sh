#!/bin/bash

# Interactive Claude Code Shell
set -euo pipefail

usage() {
    echo "Usage: $0 [--input-dir PATH] [--output-dir PATH] [--data-dir PATH] [claude args...]"
    echo ""
    echo "Runs the Claude Code container in Docker with:"
    echo "  - input directory mounted read-only at /workspace/input"
    echo "  - output directory mounted read-write at /workspace/output"
    echo "  - optional data directory mounted read-only at /workspace/data"
    echo ""
    echo "Options:"
    echo "  --input-dir PATH    Directory to mount as input (default: current directory)"
    echo "  --output-dir PATH   Directory to mount as output (default: ./reports)"
    echo "  --data-dir PATH     Optional data directory to mount"
    echo ""
    echo "Environment:"
    echo "  CLAUDE_CODE_OAUTH_TOKEN   Claude Code OAuth token"
}

INPUT_DIR="$(pwd)"
OUTPUT_DIR="$(pwd)/reports"
DATA_DIR=""
CLAUDE_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --input-dir)
            if [[ $# -lt 2 ]]; then
                echo "❌ Error: --input-dir requires a value"
                exit 1
            fi
            INPUT_DIR="$2"
            shift 2
            ;;
        --output-dir)
            if [[ $# -lt 2 ]]; then
                echo "❌ Error: --output-dir requires a value"
                exit 1
            fi
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --data-dir)
            if [[ $# -lt 2 ]]; then
                echo "❌ Error: --data-dir requires a value"
                exit 1
            fi
            DATA_DIR="$2"
            shift 2
            ;;
        --)
            shift
            CLAUDE_ARGS+=("$@")
            break
            ;;
        *)
            CLAUDE_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ ! -d "$INPUT_DIR" ]]; then
    echo "❌ Error: Input directory '$INPUT_DIR' does not exist"
    exit 1
fi

if [[ -n "$DATA_DIR" && ! -d "$DATA_DIR" ]]; then
    echo "❌ Error: Data directory '$DATA_DIR' does not exist"
    exit 1
fi

if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
    echo "⚠️  Warning: CLAUDE_CODE_OAUTH_TOKEN not set. Claude Code may not work properly."
    echo "   Set it with: export CLAUDE_CODE_OAUTH_TOKEN='your-oauth-token'"
    echo ""
fi

mkdir -p "$OUTPUT_DIR"

DOCKER_ARGS=(
    "run" "-it" "--rm"
    "--cap-drop=ALL"
    "--security-opt=no-new-privileges:true"
    "--tmpfs" "/tmp:noexec,nosuid,size=100m"
    "--tmpfs" "/workspace/temp:noexec,nosuid,size=2g"
    "--pids-limit=100"
    "--network=bridge"
    "--add-host=host.docker.internal:127.0.0.1"
    "-v" "${INPUT_DIR}:/workspace/input:ro"
    "-v" "${OUTPUT_DIR}:/workspace/output:rw"
    "-e" "CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN:-}"
)

if [[ -n "$DATA_DIR" ]]; then
    DOCKER_ARGS+=("-v" "${DATA_DIR}:/workspace/data:ro")
    echo "📚 Using reference data from: $DATA_DIR"
fi

echo "🚀 Starting Claude Code in interactive mode..."
echo "📁 Input: $INPUT_DIR"
echo "📊 Output: $OUTPUT_DIR"
if [[ ${#CLAUDE_ARGS[@]} -gt 0 ]]; then
    echo "🔧 Claude options: ${CLAUDE_ARGS[*]}"
fi
echo ""

docker "${DOCKER_ARGS[@]}" proveo/claude-code "${CLAUDE_ARGS[@]}"
