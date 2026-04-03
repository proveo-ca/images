#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARIANT="mcp"
IMAGE=""
ARGS=()

usage() {
  cat <<'EOF'
Usage:
  ./run.sh [--variant mcp|solo] [--image <image>] [variant run args...]

Runs the claudecode harness. The default variant is mcp.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --variant)
      [[ $# -ge 2 ]] || { echo "--variant requires a value" >&2; exit 1; }
      VARIANT="$2"
      shift 2
      ;;
    --image)
      [[ $# -ge 2 ]] || { echo "--image requires a value" >&2; exit 1; }
      IMAGE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      ARGS+=("$@")
      break
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

case "$VARIANT" in
  mcp)
    export PROVEO_CLAUDECODE_IMAGE="${IMAGE:-${PROVEO_CLAUDECODE_IMAGE:-proveo/claudecode:latest}}"
    exec "$SCRIPT_DIR/mcp/run.sh" "${ARGS[@]}"
    ;;
  solo)
    export PROVEO_CLAUDECODE_SOLO_IMAGE="${IMAGE:-${PROVEO_CLAUDECODE_SOLO_IMAGE:-proveo/claudecode-solo:latest}}"
    exec "$SCRIPT_DIR/solo/run.sh" "${ARGS[@]}"
    ;;
  *)
    echo "Unknown claudecode variant: $VARIANT" >&2
    usage
    exit 1
    ;;
esac
