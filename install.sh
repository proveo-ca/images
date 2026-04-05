#!/usr/bin/env bash
set -euo pipefail

INSTALL_BASE_URL="${PROVEO_INSTALL_BASE_URL:-https://proveo.ca/images}"
INSTALL_ROOT="${PROVEO_INSTALL_ROOT:-$HOME/.proveo}"
INSTALL_BIN_DIR="$INSTALL_ROOT/bin"
PROVEO_BIN="$INSTALL_BIN_DIR/proveo"
HELP_BIN="$INSTALL_BIN_DIR/help.sh"
UNINSTALL_BIN="$INSTALL_ROOT/uninstall.sh"

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

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      echo "amd64"
      ;;
    arm64|aarch64)
      echo "arm64"
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

path_export_line() {
  local shell_name="$1"

  case "$shell_name" in
    fish)
      echo "fish_add_path \"$INSTALL_BIN_DIR\""
      ;;
    *)
      echo "export PATH=\"$INSTALL_BIN_DIR:\$PATH\""
      ;;
  esac
}

path_already_configured() {
  local rc_file="$1"

  [[ -f "$rc_file" ]] || return 1
  grep -Fqs "$INSTALL_BIN_DIR" "$rc_file"
}

download_file() {
  local source_url="$1"
  local destination="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$source_url" -o "$destination"
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -qO "$destination" "$source_url"
    return 0
  fi

  print_error "Neither curl nor wget is available to download required files."
  exit 1
}

install_remote_files() {
  mkdir -p "$INSTALL_BIN_DIR"

  print_info "Downloading proveo CLI..."
  download_file "$INSTALL_BASE_URL/bin/proveo" "$PROVEO_BIN"
  download_file "$INSTALL_BASE_URL/bin/help.sh" "$HELP_BIN"
  download_file "$INSTALL_BASE_URL/uninstall.sh" "$UNINSTALL_BIN"

  chmod +x "$PROVEO_BIN" "$HELP_BIN" "$UNINSTALL_BIN"
  print_success "Installed proveo files into $INSTALL_ROOT"
}

docker_install_instructions() {
  local os="$1"
  local arch="$2"

  echo ""
  print_info "Docker is required to run proveo containers."
  case "$os" in
    macos)
      echo "Install Docker Desktop for Mac:"
      echo "  https://docs.docker.com/desktop/setup/install/mac-install/"
      if [[ "$arch" == "arm64" ]]; then
        echo "Detected Apple Silicon (arm64). Use the Apple chip Docker Desktop build."
      fi
      ;;
    linux)
      echo "Install Docker Engine:"
      echo "  https://docs.docker.com/engine/install/"
      echo ""
      echo "Typical post-install step on Linux:"
      echo "  sudo usermod -aG docker \$USER"
      echo "  newgrp docker"
      ;;
    windows)
      echo "Install Docker Desktop for Windows:"
      echo "  https://docs.docker.com/desktop/setup/install/windows-install/"
      ;;
    *)
      echo "Install Docker from:"
      echo "  https://docs.docker.com/get-docker/"
      ;;
  esac
}

check_docker() {
  local os="$1"
  local arch="$2"

  if command -v docker >/dev/null 2>&1; then
    print_success "Docker is installed: $(docker --version 2>/dev/null || echo docker)"
    return 0
  fi

  print_error "Docker was not found on this machine."
  docker_install_instructions "$os" "$arch"
  echo ""
  print_info "After installing Docker, rerun this installer or start using:"
  echo "  proveo help"
}

configure_path() {
  local os="$1"
  local shell_name="$2"
  local rc_file
  local export_line

  if [[ "$os" == "windows" ]]; then
    print_error "Automatic shell PATH setup is not supported on Windows by this installer."
    print_info "Please add this directory to your PATH manually:"
    print_info "  $INSTALL_BIN_DIR"
    return 1
  fi

  rc_file="$(shell_rc_file "$os" "$shell_name")"
  if [[ -z "$rc_file" ]]; then
    print_error "Unsupported or unknown shell: $shell_name"
    print_info "Please add this directory to your PATH manually:"
    print_info "  $INSTALL_BIN_DIR"
    return 1
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
    print_success "Added $INSTALL_BIN_DIR to PATH in $rc_file"
  fi

  echo ""
  print_info "Open a new shell, or run:"
  echo "  source \"$rc_file\""
  return 0
}

main() {
  local os
  local arch
  local shell_name

  os="$(detect_os)"
  arch="$(detect_arch)"
  shell_name="$(detect_shell_name)"

  print_info "Detected OS: $os"
  print_info "Detected architecture: $arch"
  print_info "Detected shell: $shell_name"
  print_info "Install source: $INSTALL_BASE_URL"
  print_info "Install destination: $INSTALL_ROOT"

  install_remote_files
  configure_path "$os" "$shell_name" || true
  check_docker "$os" "$arch"

  echo ""
  print_success "Installation complete."
  print_info "Available commands:"
  echo "  proveo help"
  echo "  proveo list"
  echo "  proveo run aider-node"
}

main "$@"
