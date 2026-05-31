#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="${PROVEO_INSTALL_ROOT:-$HOME/.proveo}"
BIN_DIR="$INSTALL_ROOT/bin"

PATH_MARKER_START="# Added by proveo install.sh"
PATH_MARKER_END="# End added by proveo install.sh"

print_info() {
  printf '%s\n' "$*"
}

remove_path_block() {
  local config_file="$1"
  local tmp_file

  [[ -f "$config_file" ]] || return 0
  grep -Fq "$PATH_MARKER_START" "$config_file" || return 0

  tmp_file="$(mktemp)"
  awk -v start="$PATH_MARKER_START" -v end="$PATH_MARKER_END" '
    $0 == start { skip = 1; next }
    $0 == end { skip = 0; next }
    skip != 1 { print }
  ' "$config_file" > "$tmp_file"
  mv "$tmp_file" "$config_file"

  print_info "Removed proveo PATH block from $config_file"
}

confirm_uninstall() {
  if [[ "${PROVEO_UNINSTALL_ASSUME_YES:-}" == "1" ]]; then
    return 0
  fi

  printf 'This will remove proveo from %s. Continue? [y/N] ' "$INSTALL_ROOT"
  read -r answer
  case "$answer" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      print_info "Uninstall cancelled."
      exit 0
      ;;
  esac
}

confirm_uninstall

remove_path_block "$HOME/.zshrc"
remove_path_block "$HOME/.bashrc"
remove_path_block "$HOME/.bash_profile"
remove_path_block "$HOME/.profile"
remove_path_block "$HOME/.config/fish/config.fish"

rm -f "$BIN_DIR/proveo" "$BIN_DIR/help.sh" "$INSTALL_ROOT/uninstall.sh"
rmdir "$BIN_DIR" 2>/dev/null || true
rmdir "$INSTALL_ROOT" 2>/dev/null || true

print_info "proveo uninstalled. Open a new shell for PATH changes to take effect."
