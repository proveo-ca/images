#!/usr/bin/env bash
# Consumer runners: list metadata + exec Go proveo.
# Targets/images prefer defs/*/harness.manifest when available.

# shellcheck disable=SC1091
if [[ -f "${PROVEO_LIB_DIR:-}/manifest-enum.sh" ]]; then
  # shellcheck source=/dev/null
  source "${PROVEO_LIB_DIR}/manifest-enum.sh"
elif [[ -n "${REPO_ROOT:-}" && -f "$REPO_ROOT/lib/manifest-enum.sh" ]]; then
  # shellcheck source=/dev/null
  source "$REPO_ROOT/lib/manifest-enum.sh"
fi

# Fallback when defs tree is not installed with the consumer CLI.
_PROVEO_FALLBACK_TARGETS=(cecli cecli-node opencode claudecode claudecode-solo claudecode-sol cursor)

image_name() {
  local target="$1" img
  case "$target" in
    base) echo "proveo/base"; return 0 ;;
    egress-proxy) echo "proveo/egress-proxy"; return 0 ;;
    mitmproxy) echo "proveo/mitmproxy"; return 0 ;;
  esac
  if type proveo_manifest_image >/dev/null 2>&1; then
    if img="$(proveo_manifest_image "$target" 2>/dev/null)" && [[ -n "$img" ]]; then
      printf '%s\n' "${img%%:*}"
      return 0
    fi
  fi
  case "$target" in
    cecli) echo "proveo/cecli" ;;
    cecli-node) echo "proveo/cecli-node" ;;
    opencode) echo "proveo/opencode" ;;
    claudecode) echo "proveo/claudecode" ;;
    claudecode-solo) echo "proveo/claudecode-solo" ;;
    claudecode-sol) echo "proveo/claudecode-sol" ;;
    cursor) echo "proveo/cursor" ;;
    *)
      print_error "Unknown image target: $target"
      exit 1
      ;;
  esac
}

target_description() {
  local target="$1" d
  if type proveo_manifest_description >/dev/null 2>&1; then
    if d="$(proveo_manifest_description "$target" 2>/dev/null)" && [[ -n "$d" ]]; then
      printf '%s\n' "$d"
      return 0
    fi
  fi
  case "$target" in
    cecli) echo "cecli (Python)" ;;
    cecli-node) echo "cecli (Node)" ;;
    opencode) echo "opencode with baked-in Proveo defaults" ;;
    claudecode) echo "Claude Code (MCP)" ;;
    claudecode-solo|claudecode-sol) echo "Claude Code (solo)" ;;
    cursor) echo "Cursor CLI (policy-gated)" ;;
    *) echo "$target" ;;
  esac
}

proveo_bin() {
  if [[ -n "${PROVEO_BIN:-}" ]]; then
    printf '%s\n' "$PROVEO_BIN"
    return 0
  fi
  if command -v proveo >/dev/null 2>&1; then
    command -v proveo
    return 0
  fi
  print_error "proveo binary not found on PATH. Install via dist/install.sh or set PROVEO_BIN."
  exit 1
}

ensure_docker_available() {
  if ! command -v docker >/dev/null 2>&1; then
    print_error "Docker is required but was not found on PATH."
    exit 1
  fi
}

run_target() {
  local target="$1"
  shift
  ensure_docker_available
  local bin
  bin="$(proveo_bin)"
  local run_target="$target"
  [[ "$target" == "claudecode-sol" ]] && run_target="claudecode-solo"
  exec "$bin" run "$run_target" "$@"
}
