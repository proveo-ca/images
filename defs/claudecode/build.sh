#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARIANT="all"
TAG="latest"
NO_CACHE=""

usage() {
  cat <<'EOF'
Usage:
  ./build.sh [--variant mcp|solo|all] [--tag <tag>] [--no-cache]

Builds the claudecode harness images. Defaults to all variants.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --variant)
      [[ $# -ge 2 ]] || { echo "--variant requires a value" >&2; exit 1; }
      VARIANT="$2"
      shift 2
      ;;
    --tag)
      [[ $# -ge 2 ]] || { echo "--tag requires a value" >&2; exit 1; }
      TAG="$2"
      shift 2
      ;;
    --no-cache)
      NO_CACHE="--no-cache"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown build option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

build_variant() {
  local variant="$1"
  local image="$2"
  echo "Building $image:$TAG from $variant..."
  docker build ${NO_CACHE:+$NO_CACHE} -t "$image:$TAG" -f "$SCRIPT_DIR/$variant/Dockerfile" "$SCRIPT_DIR/$variant"
}

case "$VARIANT" in
  mcp)
    build_variant mcp proveo/claudecode
    ;;
  solo)
    build_variant solo proveo/claudecode-solo
    ;;
  all)
    build_variant mcp proveo/claudecode
    build_variant solo proveo/claudecode-solo
    ;;
  *)
    echo "Unknown variant: $VARIANT" >&2
    usage
    exit 1
    ;;
esac
