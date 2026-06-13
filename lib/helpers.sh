#!/usr/bin/env bash
# Maintainer helpers for proveo CLI

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

run_uninstall() {
  if [[ ! -f "$CONSUMER_UNINSTALL_SCRIPT" ]]; then
    print_error "Consumer uninstall script not found: $CONSUMER_UNINSTALL_SCRIPT"
    exit 1
  fi

  "$CONSUMER_UNINSTALL_SCRIPT"
}

run_init() {
  if [[ ! -f "$CONSUMER_INIT_SCRIPT" ]]; then
    print_error "Consumer init script not found: $CONSUMER_INIT_SCRIPT"
    exit 1
  fi

  "$CONSUMER_INIT_SCRIPT"
}
