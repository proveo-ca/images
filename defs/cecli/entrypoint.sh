#!/usr/bin/env bash
set -euo pipefail

if [[ -d /app ]]; then
  cd /app
fi

: "${CECLI_HOME:=/app/.cecli}"
: "${LOCAL_UID:=1000}"
: "${LOCAL_GID:=1000}"

export CECLI_HOME

if [[ "$(id -u)" = "0" ]]; then
  mkdir -p "$CECLI_HOME"

  if ! getent group "$LOCAL_GID" >/dev/null 2>&1; then
    groupadd -g "$LOCAL_GID" cecli
  fi

  if ! getent passwd "$LOCAL_UID" >/dev/null 2>&1; then
    useradd -m -u "$LOCAL_UID" -g "$LOCAL_GID" -s /bin/bash cecli
  fi

  runtime_home="$(getent passwd "$LOCAL_UID" | cut -d: -f6 || true)"
  if [[ -n "$runtime_home" ]]; then
    mkdir -p "$runtime_home"
    chown "$LOCAL_UID:$LOCAL_GID" "$runtime_home" 2>/dev/null || true
    export HOME="$runtime_home"
  fi

  chown -R "$LOCAL_UID:$LOCAL_GID" "$CECLI_HOME" 2>/dev/null || true

  exec gosu "$LOCAL_UID:$LOCAL_GID" "$0" "$@"
fi

mkdir -p "$CECLI_HOME" 2>/dev/null || true

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
  echo "✅ Loaded environment variables from .env"
fi

# ── Environment Variable Bridge ────────────────────────────
# Standardized vars:
#   ARCHITECT_MODEL -> CECLI_MODEL / AIDER_MODEL
#   EDITOR_MODEL    -> CECLI_EDITOR_MODEL / AIDER_EDITOR_MODEL
#   SMALL_MODEL     -> CECLI_WEAK_MODEL / AIDER_WEAK_MODEL
#   DARK_MODE=true  -> CECLI_DARK_MODE / AIDER_DARK_MODE
#   CODE_THEME      -> CECLI_CODE_THEME
#
# CECLI is an aider fork, so both CECLI_* and AIDER_* names are exported
# unless the caller already set a more specific value.
if [[ -n "${ARCHITECT_MODEL:-}" ]]; then
  export CECLI_MODEL="${CECLI_MODEL:-$ARCHITECT_MODEL}"
  export AIDER_MODEL="${AIDER_MODEL:-$ARCHITECT_MODEL}"
fi

if [[ -n "${EDITOR_MODEL:-}" ]]; then
  export CECLI_EDITOR_MODEL="${CECLI_EDITOR_MODEL:-$EDITOR_MODEL}"
  export AIDER_EDITOR_MODEL="${AIDER_EDITOR_MODEL:-$EDITOR_MODEL}"
fi

if [[ -n "${SMALL_MODEL:-}" ]]; then
  export CECLI_WEAK_MODEL="${CECLI_WEAK_MODEL:-$SMALL_MODEL}"
  export AIDER_WEAK_MODEL="${AIDER_WEAK_MODEL:-$SMALL_MODEL}"
fi

case "${DARK_MODE:-}" in
  true|TRUE|True|1|yes|YES|Yes)
    export CECLI_DARK_MODE="${CECLI_DARK_MODE:-true}"
    export AIDER_DARK_MODE="${AIDER_DARK_MODE:-true}"
    ;;
esac

if [[ -n "${CODE_THEME:-}" ]]; then
  export CECLI_CODE_THEME="${CECLI_CODE_THEME:-$CODE_THEME}"
fi

echo "cecli version:      $(cecli --version 2>/dev/null || echo 'installed')"

if command -v curl >/dev/null 2>&1; then
  echo "curl version:       $(curl --version | head -n1)"
fi

if command -v npm >/dev/null 2>&1; then
  echo "npm version:        $(npm -v)"
fi

if command -v pnpm >/dev/null 2>&1; then
  echo "pnpm version:       $(pnpm -v)"
fi

if [[ -n "${CECLI_MODEL:-${AIDER_MODEL:-}}" ]]; then
  echo "model:              ${CECLI_MODEL:-${AIDER_MODEL:-}}"
fi

if [[ -n "${CECLI_EDITOR_MODEL:-${AIDER_EDITOR_MODEL:-}}" ]]; then
  echo "editor model:       ${CECLI_EDITOR_MODEL:-${AIDER_EDITOR_MODEL:-}}"
fi

if [[ -n "${CECLI_WEAK_MODEL:-${AIDER_WEAK_MODEL:-}}" ]]; then
  echo "weak model:         ${CECLI_WEAK_MODEL:-${AIDER_WEAK_MODEL:-}}"
fi

if [[ -n "${CECLI_DARK_MODE:-${AIDER_DARK_MODE:-}}" ]]; then
  echo "dark mode:          ${CECLI_DARK_MODE:-${AIDER_DARK_MODE:-}}"
fi

if [[ -n "${CECLI_CODE_THEME:-}" ]]; then
  echo "code theme:         $CECLI_CODE_THEME"
fi

echo "── Configuration Check ──────────────────────────────"
if [[ -f .cecli.conf.yml ]]; then
  echo "✅ Found .cecli.conf.yml"
elif [[ -f .cecli.conf.yaml ]]; then
  echo "✅ Found .cecli.conf.yaml"
else
  echo "🔎 Not found .cecli.conf.yml"
fi

if [[ -f .cecliignore ]]; then echo "✅ Found .cecliignore"; else echo "🔎 Not found .cecliignore"; fi
if [[ -f CONVENTIONS.md ]]; then echo "✅ Found CONVENTIONS.md"; else echo "🔎 Not found CONVENTIONS.md"; fi
echo "─────────────────────────────────────────────────────"

ensure_node_deps() {
  if [[ "${CECLI_INSTALL_NODE_DEPS:-0}" != "1" ]]; then
    return
  fi

  if ! command -v npm >/dev/null 2>&1; then
    return
  fi

  if [[ ! -f package.json ]]; then
    return
  fi

  if [[ -d node_modules ]]; then
    return
  fi

  echo "No node_modules found in $(pwd); installing dependencies..."

  if command -v pnpm >/dev/null 2>&1 && [[ -f pnpm-lock.yaml ]]; then
    pnpm install --frozen-lockfile
  elif [[ -f package-lock.json ]]; then
    npm ci
  else
    npm install
  fi
}

ensure_node_deps

if [[ $# -eq 0 ]]; then
  set -- cecli
elif [[ "$1" == -* ]]; then
  set -- cecli "$@"
elif [[ "$1" != "cecli" && "$1" != "bash" && "$1" != "sh" && "$1" != "python" && "$1" != "python3" && "$1" != "node" && "$1" != "npm" && "$1" != "pnpm" && "$1" != "git" && "$1" != "curl" ]]; then
  set -- cecli "$@"
fi

exec "$@"
