#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${PROVEO_MITMPROXY_IMAGE:-proveo/mitmproxy:latest}"
FLOWS_DIR="$PWD/flows"
CONFDIR="$PWD/confdir"
PORT="8888"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      IMAGE_NAME="$2"; shift 2 ;;
    --flows-dir)
      FLOWS_DIR="$2"; shift 2 ;;
    --confdir)
      CONFDIR="$2"; shift 2 ;;
    --port)
      PORT="$2"; shift 2 ;;
    *)
      echo "Unknown debug option: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$FLOWS_DIR" "$CONFDIR"

docker run -it --rm \
  --entrypoint /bin/bash \
  -p "$PORT:8888" \
  -v "$FLOWS_DIR:/flows" \
  -v "$CONFDIR:/mitmproxy-confdir" \
  "$IMAGE_NAME"
