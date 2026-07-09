#!/usr/bin/env bash
# Maintainer runners — targets/images from harness.manifest; run/debug → proveo.

# shellcheck source=manifest-enum.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/manifest-enum.sh"

# Build TARGETS: base first, then every image key from manifests, then sidecars.
_proveo_build_maintainer_targets() {
  local -a harness=()
  local t
  if proveo_load_manifest_targets 2>/dev/null; then
    harness=("${MANIFEST_TARGETS[@]}")
  else
    harness=(cecli cecli-node opencode claudecode claudecode-solo claudecode-sol cursor)
  fi
  TARGETS=("base")
  for t in "${harness[@]}"; do
    TARGETS+=("$t")
  done
  TARGETS+=("egress-proxy" "mitmproxy")
}
_proveo_build_maintainer_targets

image_name() {
  local target="$1"
  local img
  case "$target" in
    base) echo "proveo/base"; return 0 ;;
    egress-proxy) echo "proveo/egress-proxy"; return 0 ;;
    mitmproxy) echo "proveo/mitmproxy"; return 0 ;;
  esac
  if img="$(proveo_manifest_image "$target" 2>/dev/null)" && [[ -n "$img" ]]; then
    # Strip :tag for org/name used by build
    printf '%s\n' "${img%%:*}"
    return 0
  fi
  print_error "No image mapping for target: $target"
  exit 1
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
  local candidate="${REPO_ROOT:-}/bin/proveo"
  if [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  printf 'proveo\n'
}

target_dir() {
  local target="$1"
  local d
  case "$target" in
    base) echo "${REPO_ROOT}/defs/base"; return 0 ;;
    egress-proxy) echo "${REPO_ROOT}/defs/sidecars/egress-proxy"; return 0 ;;
    mitmproxy) echo "${REPO_ROOT}/defs/sidecars/mitmproxy"; return 0 ;;
  esac
  if d="$(proveo_manifest_dir "$target" 2>/dev/null)" && [[ -n "$d" ]]; then
    printf '%s\n' "$d"
    return 0
  fi
  print_error "No directory mapping for target: $target"
  exit 1
}

run_target() {
  local target="$1"
  local tag="$2"
  shift 2
  local -a extra_args=("$@")
  local bin run_t
  bin="$(proveo_bin)"
  run_t="$target"
  [[ "$target" == "claudecode-sol" ]] && run_t="claudecode-solo"

  if ! proveo_manifest_image "$run_t" >/dev/null 2>&1 && [[ "$run_t" != "claudecode-solo" ]]; then
    # claudecode-sol is a build target; run uses claudecode-solo image name from manifest
    if ! proveo_manifest_image "$target" >/dev/null 2>&1; then
      print_error "Unsupported run target: $target"
      exit 1
    fi
  fi

  local -a args=(run "$run_t")
  if [[ -n "$tag" && "$tag" != "latest" ]]; then
    args+=(--image "$(image_name "$run_t"):$tag")
  fi
  "$bin" "${args[@]}" ${extra_args[@]+"${extra_args[@]}"}
}

debug_target() {
  local target="$1"
  local tag="$2"
  shift 2
  local -a extra_args=("$@")
  local bin run_t
  bin="$(proveo_bin)"
  run_t="$target"
  [[ "$target" == "claudecode-sol" ]] && run_t="claudecode-solo"

  local -a args=(run "$run_t" --shell)
  if [[ -n "$tag" && "$tag" != "latest" ]]; then
    args+=(--image "$(image_name "$run_t"):$tag")
  fi
  "$bin" "${args[@]}" ${extra_args[@]+"${extra_args[@]}"}
}
