#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARIANT="all"
TAG="latest"
NO_CACHE=""

usage() {
  cat <<'EOF'
Usage:
  ./build.sh [--variant mcp|solo|sol|all] [--tag <tag>] [--no-cache]

Builds the claudecode harness images. Defaults to all variants.
sol = mcp + the Solidity/security toolchain (Foundry, solc, solhint, semgrep).
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
  docker build ${NO_CACHE:+$NO_CACHE} -t "$image:$TAG" -f "$SCRIPT_DIR/$variant/Dockerfile" "$SCRIPT_DIR/../.."
}

# sol layers the Solidity/security toolchain (Foundry, solc, solhint, semgrep)
# on the mcp image: ensure the same-tag parent exists, then build FROM it.
build_sol() {
  if ! docker image inspect "proveo/claudecode:$TAG" >/dev/null 2>&1; then
    build_variant mcp proveo/claudecode
  fi
  echo "Building proveo/claudecode-sol:$TAG from sol..."
  docker build ${NO_CACHE:+$NO_CACHE} \
    --build-arg BASE_IMAGE="proveo/claudecode:$TAG" \
    -t "proveo/claudecode-sol:$TAG" -f "$SCRIPT_DIR/sol/Dockerfile" "$SCRIPT_DIR/../.."
}

# mcp/solo build FROM proveo/base-node
"$SCRIPT_DIR/../base-node/ensure.sh"

case "$VARIANT" in
  mcp)
    build_variant mcp proveo/claudecode
    ;;
  solo)
    build_variant solo proveo/claudecode-solo
    ;;
  sol)
    build_sol
    ;;
  all)
    build_variant mcp proveo/claudecode
    build_variant solo proveo/claudecode-solo
    build_sol
    ;;
  *)
    echo "Unknown variant: $VARIANT" >&2
    usage
    exit 1
    ;;
esac
