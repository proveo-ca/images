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

seed_cecli_subagents() {
  local src="/opt/cecli/defaults/agents"
  local dst="$CECLI_HOME/agents"
  local seeded=()

  mkdir -p "$dst" 2>/dev/null || true
  if [[ ! -d "$src" || ! -d "$dst" ]]; then
    return
  fi

  for f in "$src/"*.md; do
    [[ -e "$f" ]] || continue
    local name; name="$(basename "$f")"
    if [[ "${CECLI_RESEED:-0}" == "1" || ! -f "$dst/$name" ]]; then
      if cp -f "$f" "$dst/$name" 2>/dev/null; then
        seeded+=("agents/$name")
      fi
    fi
  done

  if (( ${#seeded[@]} > 0 )); then
    echo "🌱 Seeded Cecli subagents into $dst: ${seeded[*]}"
  fi
}

has_cecli_agent_config() {
  local config_file
  for config_file in .cecli.config.yml .cecli.config.yaml .cecli.conf.yml .cecli.conf.yaml; do
    [[ -f "$config_file" ]] || continue
    if grep -qE '^[[:space:]]*agent-config:' "$config_file"; then
      return 0
    fi
  done
  return 1
}

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

seed_cecli_subagents

if [[ -z "${CECLI_AGENT_CONFIG:-}" ]] && ! has_cecli_agent_config; then
  CECLI_AGENT_CONFIG="{\"large_file_token_threshold\":8192,\"skip_cli_confirmations\":false,\"subagent_paths\":[\"$CECLI_HOME/agents\",\"/app/.cecli/agents\"]}"
  export CECLI_AGENT_CONFIG
fi

command_version() {
  local fallback="$1"; shift
  timeout 5s "$@" 2>/dev/null || echo "$fallback"
}

echo "cecli version:      $(command_version installed cecli --version)"

if command -v curl >/dev/null 2>&1; then
  echo "curl version:       $(command_version unknown curl --version | head -n1)"
fi

if command -v npm >/dev/null 2>&1; then
  echo "npm version:        $(command_version unknown npm -v)"
fi

if command -v pnpm >/dev/null 2>&1; then
  echo "pnpm version:       $(command_version n/a pnpm -v)"
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
if [[ -f .cecli.config.yml ]]; then
  echo "✅ Found .cecli.config.yml"
elif [[ -f .cecli.config.yaml ]]; then
  echo "✅ Found .cecli.config.yaml"
elif [[ -f .cecli.conf.yml ]]; then
  echo "✅ Found .cecli.conf.yml"
elif [[ -f .cecli.conf.yaml ]]; then
  echo "✅ Found .cecli.conf.yaml"
else
  echo "🔎 Not found .cecli.config.yml"
fi

if [[ -f .cecliignore ]]; then echo "✅ Found .cecliignore"; else echo "🔎 Not found .cecliignore"; fi
if [[ -f CONVENTIONS.md ]]; then echo "✅ Found CONVENTIONS.md"; else echo "🔎 Not found CONVENTIONS.md"; fi
if [[ -d "$CECLI_HOME/agents" ]]; then
  subagent_files=()
  while IFS= read -r f; do subagent_files+=("@$(basename "${f%.md}")"); done \
    < <(find "$CECLI_HOME/agents" -maxdepth 1 -name '*.md' 2>/dev/null | sort)
  if (( ${#subagent_files[@]} > 0 )); then
    echo "🧑‍💻 Subagents available: ${subagent_files[*]}"
  fi
fi
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
