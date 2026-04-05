#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="${PROVEO_INSTALL_ROOT:-$HOME/.proveo}"
BIN_DIR="$INSTALL_ROOT/bin"
MARKER_LINE="# Added by proveo install.sh"

print_info() {
  echo "ℹ️  $*"
}

print_success() {
  echo "✅ $*"
}

print_error() {
  echo "❌ $*" >&2
}

detect_os() {
  case "$(uname -s)" in
    Darwin)
      echo "macos"
      ;;
    Linux)
      echo "linux"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      echo "windows"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

detect_shell_name() {
  local shell_path="${SHELL:-}"
  if [[ -z "$shell_path" ]]; then
    echo "unknown"
    return 0
  fi

  basename "$shell_path"
}

shell_rc_file() {
  local os="$1"
  local shell_name="$2"
  local home_dir="${HOME:-}"

  case "$shell_name" in
    bash)
      if [[ "$os" == "macos" ]]; then
        echo "$home_dir/.bash_profile"
      else
        if [[ -f "$home_dir/.bashrc" ]]; then
          echo "$home_dir/.bashrc"
        elif [[ -f "$home_dir/.bash_profile" ]]; then
          echo "$home_dir/.bash_profile"
        else
          echo "$home_dir/.bashrc"
        fi
      fi
      ;;
    zsh)
      echo "$home_dir/.zshrc"
      ;;
    fish)
      echo "$home_dir/.config/fish/config.fish"
      ;;
    *)
      echo ""
      ;;
  esac
}

confirm_uninstall() {
  local answer
  echo "⚠️  This will remove proveo from your shell PATH configuration."
  echo "   PATH entry: $BIN_DIR"
  echo "   Install root: $INSTALL_ROOT"
  echo ""
  read -r -p "Continue with uninstall? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      print_info "Uninstall canceled."
      exit 0
      ;;
  esac
}

remove_path_lines() {
  local rc_file="$1"
  [[ -f "$rc_file" ]] || return 0

  python3 - "$rc_file" "$BIN_DIR" "$MARKER_LINE" <<'PY'
import sys
from pathlib import Path

rc_file = Path(sys.argv[1])
bin_dir = sys.argv[2]
marker = sys.argv[3]

lines = rc_file.read_text().splitlines()
result = []
skip_blank_after_marker = False

for line in lines:
    stripped = line.strip()
    if stripped == marker.strip():
        skip_blank_after_marker = True
        continue
    if bin_dir in line:
        continue
    if skip_blank_after_marker and stripped == "":
        skip_blank_after_marker = False
        continue
    skip_blank_after_marker = False
    result.append(line)

content = "\n".join(result)
if lines:
    content += "\n"
rc_file.write_text(content)
PY
}

main() {
  local os
  local shell_name
  local rc_file

  os="$(detect_os)"
  shell_name="$(detect_shell_name)"

  print_info "Detected OS: $os"
  print_info "Detected shell: $shell_name"

  if [[ "$os" == "windows" ]]; then
    print_error "Automatic uninstall is not supported on Windows by this script."
    print_info "Please remove this directory from PATH manually:"
    print_info "  $BIN_DIR"
    exit 1
  fi

  rc_file="$(shell_rc_file "$os" "$shell_name")"
  if [[ -z "$rc_file" ]]; then
    print_error "Unsupported or unknown shell: $shell_name"
    print_info "Please remove this directory from PATH manually:"
    print_info "  $BIN_DIR"
    exit 1
  fi

  confirm_uninstall

  mkdir -p "$(dirname "$rc_file")"
  touch "$rc_file"

  remove_path_lines "$rc_file"

  rm -f "$BIN_DIR/proveo" "$BIN_DIR/help.sh"
  rmdir "$BIN_DIR" 2>/dev/null || true
  rm -f "$INSTALL_ROOT/uninstall.sh"
  rmdir "$INSTALL_ROOT" 2>/dev/null || true

  print_success "Removed proveo PATH entries from $rc_file"
  echo ""
  print_info "Open a new shell, or run:"
  echo "  source \"$rc_file\""
}

main "$@"
