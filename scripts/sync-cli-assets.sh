#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC_INSTALL="$REPO_ROOT/install.sh"
SRC_UNINSTALL="$REPO_ROOT/uninstall.sh"
SRC_PROVEO="$REPO_ROOT/bin/proveo"
SRC_HELP="$REPO_ROOT/bin/help.sh"

DEST_ROOT="$REPO_ROOT/apps/cli/public/images"
DEST_BIN="$DEST_ROOT/bin"

print_info() {
  echo "ℹ️  $*"
}

print_success() {
  echo "✅ $*"
}

print_error() {
  echo "❌ $*" >&2
}

require_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    print_error "Required source file not found: $file"
    exit 1
  fi
}

copy_file() {
  local src="$1"
  local dest="$2"

  cp "$src" "$dest"
  chmod +x "$dest"
  print_info "Synced $(realpath --relative-to="$REPO_ROOT" "$src") -> $(realpath --relative-to="$REPO_ROOT" "$dest")"
}

main() {
  require_file "$SRC_INSTALL"
  require_file "$SRC_UNINSTALL"
  require_file "$SRC_PROVEO"
  require_file "$SRC_HELP"

  mkdir -p "$DEST_BIN"

  copy_file "$SRC_INSTALL" "$DEST_ROOT/install.sh"
  copy_file "$SRC_UNINSTALL" "$DEST_ROOT/uninstall.sh"
  copy_file "$SRC_PROVEO" "$DEST_BIN/proveo"
  copy_file "$SRC_HELP" "$DEST_BIN/help.sh"

  print_success "CLI assets synced to apps/cli/public/images"
}

main "$@"
