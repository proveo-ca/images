#!/usr/bin/env bash
set -euo pipefail

PROVEO_VERSION="0.0.1"
INSTALL_ROOT="${PROVEO_INSTALL_ROOT:-$HOME/.proveo}"
BIN_DIR="$INSTALL_ROOT/bin"
ASSET_BASE_URL="${PROVEO_ASSET_BASE_URL:-https://proveo.ca/cli}"
CLI_BASE_URL="${PROVEO_CLI_BASE_URL:-https://proveo.ca/cli}"

PATH_MARKER_START="# Added by proveo install.sh"
PATH_MARKER_END="# End added by proveo install.sh"

print_error() {
  printf 'Error: %s\n' "$*" >&2
}

print_info() {
  printf '%s\n' "$*"
}

download_file() {
  local url="$1"
  local dest="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url"
    return 0
  fi

  print_error "curl or wget is required to install proveo."
  exit 1
}

shell_config_file() {
  local shell_name
  shell_name="$(basename "${SHELL:-sh}")"

  case "$shell_name" in
    zsh)
      printf '%s\n' "$HOME/.zshrc"
      ;;
    fish)
      mkdir -p "$HOME/.config/fish"
      printf '%s\n' "$HOME/.config/fish/config.fish"
      ;;
    bash)
      if [[ "$(uname -s)" == "Darwin" ]]; then
        printf '%s\n' "$HOME/.bash_profile"
      else
        printf '%s\n' "$HOME/.bashrc"
      fi
      ;;
    *)
      printf '%s\n' "$HOME/.profile"
      ;;
  esac
}

path_entry_for_shell() {
  local shell_name
  shell_name="$(basename "${SHELL:-sh}")"

  if [[ "$shell_name" == "fish" ]]; then
    printf 'set -gx PATH "%s" $PATH\n' "$BIN_DIR"
  else
    printf 'export PATH="%s:$PATH"\n' "$BIN_DIR"
  fi
}

ensure_path() {
  local config_file
  config_file="$(shell_config_file)"
  touch "$config_file"

  if grep -Fq "$PATH_MARKER_START" "$config_file"; then
    return 0
  fi

  {
    printf '\n%s\n' "$PATH_MARKER_START"
    path_entry_for_shell
    printf '%s\n' "$PATH_MARKER_END"
  } >> "$config_file"

  print_info "Added $BIN_DIR to PATH in $config_file"
}

check_docker() {
  if command -v docker >/dev/null 2>&1; then
    return 0
  fi

  cat <<'EOF'

Docker was not found on this machine.

proveo runs published Docker images, so Docker must be installed before running containers:
  https://docs.docker.com/get-docker/

After Docker is installed, run:
  proveo list
EOF
}

print_post_install_message() {
  local shell_name
  shell_name="$(basename "${SHELL:-sh}")"

  local path_cmd
  local reload_cmd
  local config_file
  config_file="$(shell_config_file)"
  local pretty_config="${config_file/#$HOME/\~}"

  if [[ "$shell_name" == "fish" ]]; then
    path_cmd="set -gx PATH \"$BIN_DIR\" \$PATH"
    reload_cmd="source $pretty_config"
  else
    path_cmd="export PATH=\"$BIN_DIR:\$PATH\""
    reload_cmd="source $pretty_config"
  fi

  cat <<EOF

proveo v$PROVEO_VERSION installed to:
  $BIN_DIR/proveo

Open a new shell or run:
  $path_cmd

Or reload your current configuration:
  $reload_cmd

Then try:
  proveo init
  proveo help
EOF
}

LIB_DIR="$INSTALL_ROOT/lib"

mkdir -p "$BIN_DIR" "$LIB_DIR"

download_file "$ASSET_BASE_URL/bin/proveo" "$BIN_DIR/proveo"
download_file "$ASSET_BASE_URL/bin/help.sh" "$BIN_DIR/help.sh"
download_file "$ASSET_BASE_URL/bin/init.sh" "$BIN_DIR/init.sh"
download_file "$ASSET_BASE_URL/lib/ui.sh" "$LIB_DIR/ui.sh"
download_file "$ASSET_BASE_URL/lib/manifest-enum.sh" "$LIB_DIR/manifest-enum.sh"
download_file "$ASSET_BASE_URL/lib/runners.sh" "$LIB_DIR/runners.sh"
download_file "$CLI_BASE_URL/uninstall.sh" "$INSTALL_ROOT/uninstall.sh"

chmod +x "$BIN_DIR/proveo" "$BIN_DIR/help.sh" "$BIN_DIR/init.sh" "$INSTALL_ROOT/uninstall.sh"

ensure_path
check_docker

print_post_install_message

