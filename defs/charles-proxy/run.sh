#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${PROVEO_CHARLES_PROXY_IMAGE:-proveo/charles-proxy:latest}"
SESSIONS_DIR="$PWD/sessions"
CONFIG_DIR="$PWD/config"
PORT="8888"

usage() {
  cat <<'EOF'
Usage:
  ./run.sh [--image <image>] [--sessions-dir <path>] [--config-dir <path>] [--port <port>]

Runs the headless Charles Proxy harness.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      if [[ $# -lt 2 ]]; then
        echo "--image requires a value" >&2
        exit 1
      fi
      IMAGE_NAME="$2"
      shift 2
      ;;
    --sessions-dir)
      if [[ $# -lt 2 ]]; then
        echo "--sessions-dir requires a value" >&2
        exit 1
      fi
      SESSIONS_DIR="$2"
      shift 2
      ;;
    --config-dir)
      if [[ $# -lt 2 ]]; then
        echo "--config-dir requires a value" >&2
        exit 1
      fi
      CONFIG_DIR="$2"
      shift 2
      ;;
    --port)
      if [[ $# -lt 2 ]]; then
        echo "--port requires a value" >&2
        exit 1
      fi
      PORT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown run option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

mkdir -p "$SESSIONS_DIR" "$CONFIG_DIR"

docker run -it --rm \
  -p "$PORT:8888" \
  -v "$SESSIONS_DIR:/sessions" \
  -v "$CONFIG_DIR:/config" \
  "$IMAGE_NAME"
