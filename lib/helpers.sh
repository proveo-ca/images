#!/usr/bin/env bash
# Maintainer helpers for the proveo mise tasks. The build/deploy/test
# orchestration moved to Go (`proveo build|deploy|test`); what remains here is
# used by the `debug` task (with lib/ui.sh + lib/registry.sh).

print_error() {
  echo "❌ $*" >&2
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
