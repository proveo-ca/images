#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${PROVEO_CHARLES_PROXY_IMAGE:-proveo/charles-proxy:latest}"
SESSIONS_DIR="$PWD/sessions"
CONFIG_DIR="$PWD/config"
PORT="8888"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      IMAGE_NAME="$2"
      shift 2
      ;;
    --sessions-dir)
      SESSIONS_DIR="$2"
      shift 2
      ;;
    --config-dir)
      CONFIG_DIR="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    *)
      echo "Unknown debug option: $1" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$SESSIONS_DIR" "$CONFIG_DIR"

docker run -it --rm \
  --entrypoint /bin/bash \
  -p "$PORT:8888" \
  -v "$SESSIONS_DIR:/sessions" \
  -v "$CONFIG_DIR:/config" \
  "$IMAGE_NAME"
