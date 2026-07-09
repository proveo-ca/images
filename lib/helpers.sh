#!/usr/bin/env bash
# Maintainer helpers for the proveo mise tasks. Formerly split between the
# consumer bash CLI (now retired — the consumer surface is the Go `proveo`
# binary) and lib/; these are the pieces the maintainer image tasks still use.

print_error() {
  echo "❌ $*" >&2
}

print_info() {
  echo "ℹ️  $*"
}

print_success() {
  echo "✅ $*"
}

require_tag() {
  local tag="${1:-}"
  local command_name="${2:-command}"
  if [[ -z "$tag" ]]; then
    print_error "Command '$command_name' received an empty tag."
    exit 1
  fi
}

# is_valid_target / require_target validate against TARGETS (built in
# lib/registry.sh from `proveo targets`, sourced by the same tasks). Late binding
# is fine: these run after all sources, by which point TARGETS is populated.
is_valid_target() {
  local target="$1"
  local item
  for item in "${TARGETS[@]}"; do
    if [[ "$item" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

_print_targets() {
  echo "Available targets:" >&2
  local t
  for t in "${TARGETS[@]}"; do
    echo "  - $t" >&2
  done
}

require_target() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    print_error "Missing target."
    _print_targets
    exit 1
  fi
  if ! is_valid_target "$target"; then
    print_error "Unknown target: $target"
    _print_targets
    exit 1
  fi
}

# ensure_image_available lives here (not lib/build.sh) so the deploy task —
# which sources helpers + runners + deploy.sh but NOT build.sh — can call it too.
ensure_image_available() {
  local image="$1"
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    print_error "Docker image not found locally: $image"
    print_info "Build it first with: mise run build ${2:-<target>} --tag ${DEFAULT_TAG:-latest}"
    exit 1
  fi
}

find_script_in_dir() {
  local dir="$1"
  shift
  local script_name
  for script_name in "$@"; do
    if [[ -f "$dir/$script_name" ]]; then
      echo "$dir/$script_name"
      return 0
    fi
  done
  return 1
}
