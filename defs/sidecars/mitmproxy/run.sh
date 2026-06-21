#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${PROVEO_MITMPROXY_IMAGE:-proveo/mitmproxy:latest}"
FLOWS_DIR="$PWD/flows"
CONFDIR="$PWD/confdir"
PORT="8888"
UPSTREAM="${PROVEO_MITM_UPSTREAM:-}"

usage() {
  cat <<'EOF'
Usage:
  ./run.sh [--image <image>] [--flows-dir <path>] [--confdir <path>] [--port <port>] [--upstream <url>]

Runs the headless mitmproxy inspector. With --upstream it chains to an
enforcement proxy (e.g. http://squid:3128); without it, mitmproxy proxies
directly. HTTPS interception is on; the CA is written to the confdir.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)
      if [[ $# -lt 2 ]]; then echo "--image requires a value" >&2; exit 1; fi
      IMAGE_NAME="$2"; shift 2 ;;
    --flows-dir)
      if [[ $# -lt 2 ]]; then echo "--flows-dir requires a value" >&2; exit 1; fi
      FLOWS_DIR="$2"; shift 2 ;;
    --confdir)
      if [[ $# -lt 2 ]]; then echo "--confdir requires a value" >&2; exit 1; fi
      CONFDIR="$2"; shift 2 ;;
    --port)
      if [[ $# -lt 2 ]]; then echo "--port requires a value" >&2; exit 1; fi
      PORT="$2"; shift 2 ;;
    --upstream)
      if [[ $# -lt 2 ]]; then echo "--upstream requires a value" >&2; exit 1; fi
      UPSTREAM="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown run option: $1" >&2; usage; exit 1 ;;
  esac
done

mkdir -p "$FLOWS_DIR" "$CONFDIR"

docker run -it --rm \
  -p "$PORT:8888" \
  -e "PROVEO_MITM_PORT=8888" \
  -e "PROVEO_MITM_UPSTREAM=$UPSTREAM" \
  -v "$FLOWS_DIR:/flows" \
  -v "$CONFDIR:/mitmproxy-confdir" \
  "$IMAGE_NAME"
