#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"
PROVEO_BIN="$BIN_DIR/proveo"
HELP_BIN="$BIN_DIR/help.sh"

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
        if [[ -f "$home_dir/.bash_profile" ]]; then
          echo "$home_dir/.bash_profile"
        else
          echo "$home_dir/.bash_profile"
        fi
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

path_export_line() {
  local shell_name="$1"

  case "$shell_name" in
    fish)
      echo "fish_add_path \"$BIN_DIR\""
      ;;
    *)
      echo "export PATH=\"$BIN_DIR:\$PATH\""
      ;;
  esac
}

path_already_configured() {
  local rc_file="$1"

  [[ -f "$rc_file" ]] || return 1

  grep -Fqs "$BIN_DIR" "$rc_file"
}

ensure_binaries_executable() {
  if [[ ! -f "$PROVEO_BIN" ]]; then
    print_error "Could not find $PROVEO_BIN"
    exit 1
  fi

  chmod +x "$PROVEO_BIN"
  print_success "Marked bin/proveo as executable"

  if [[ -f "$HELP_BIN" ]]; then
    chmod +x "$HELP_BIN"
    print_success "Marked bin/help.sh as executable"
  fi
}

main() {
  local os
  local shell_name
  local rc_file
  local export_line

  os="$(detect_os)"
  shell_name="$(detect_shell_name)"

  print_info "Detected OS: $os"
  print_info "Detected shell: $shell_name"

  ensure_binaries_executable

  if [[ "$os" == "windows" ]]; then
    print_error "Automatic shell PATH setup is not supported on Windows by this installer."
    print_info "Please add this directory to your PATH manually:"
    print_info "  $BIN_DIR"
    exit 1
  fi

  rc_file="$(shell_rc_file "$os" "$shell_name")"
  if [[ -z "$rc_file" ]]; then
    print_error "Unsupported or unknown shell: $shell_name"
    print_info "Please add this directory to your PATH manually:"
    print_info "  $BIN_DIR"
    exit 1
  fi

  mkdir -p "$(dirname "$rc_file")"
  touch "$rc_file"

  if path_already_configured "$rc_file"; then
    print_success "PATH already configured in $rc_file"
  else
    export_line="$(path_export_line "$shell_name")"
    {
      echo ""
      echo "# Added by proveo install.sh"
      echo "$export_line"
    } >> "$rc_file"
    print_success "Added $BIN_DIR to PATH in $rc_file"
  fi

  echo ""
  print_info "Installation complete."
  print_info "Open a new shell, or run:"
  echo "  source \"$rc_file\""
  echo ""
  print_info "Then you can run:"
  echo "  proveo help"
  echo "  proveo list"
}

main "$@"
