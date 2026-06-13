#!/usr/bin/env bash
# Shared entrypoint functions for Proveo coding harnesses

# ── 1. Set Working Directory ────────────────────────────────
set_working_directory() {
  local default_dir="${1:-/app}"
  if [[ -d "$default_dir" ]]; then
    cd "$default_dir"
  fi
}

# ── 2. Find and Load .env ───────────────────────────────────
find_env_file() {
  # 1. Check current working directory
  if [[ -f .env ]]; then
    printf '%s/.env' "$(pwd)"
    return 0
  fi

  # 2. Check git root via git command (if available)
  if command -v git >/dev/null 2>&1; then
    local git_root
    git_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$git_root" && -f "$git_root/.env" ]]; then
      printf '%s' "$git_root/.env"
      return 0
    fi
  fi

  # 3. Check git root via directory traversal (pure Bash fallback)
  local dir; dir="$(pwd)"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.git" && -f "$dir/.env" ]]; then
      printf '%s/.env' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  # 4. Check for any .env inside any subdirectories (maxdepth 5)
  local sub_env
  sub_env=$(find . -maxdepth 5 -name .env -not -path '*/node_modules/*' -not -path '*/.*/*' -print -quit 2>/dev/null)
  if [[ -n "$sub_env" && -f "$sub_env" ]]; then
    printf '%s/%s' "$(pwd)" "${sub_env#./}"
    return 0
  fi

  return 1
}

load_env() {
  local env_path; env_path="$(find_env_file || true)"
  if [[ -n "$env_path" ]]; then
    echo "✅ Found .env"
    set -a
    source "$env_path"
    set +a
    echo "✅ Loaded environment variables from .env ($env_path)"
  else
    echo "🔎 No .env found"
  fi

  # Bridge Google/Gemini API key aliases
  if [[ -z "${GOOGLE_GENERATIVE_AI_API_KEY:-}" ]]; then
    if [[ -n "${GEMINI_API_KEY:-}" ]]; then
      export GOOGLE_GENERATIVE_AI_API_KEY="$GEMINI_API_KEY"
    elif [[ -n "${GOOGLE_API_KEY:-}" ]]; then
      export GOOGLE_GENERATIVE_AI_API_KEY="$GOOGLE_API_KEY"
    fi
  fi

  # Reverse bridge for tools expecting GEMINI_API_KEY or GOOGLE_API_KEY
  if [[ -n "${GOOGLE_GENERATIVE_AI_API_KEY:-}" ]]; then
    export GEMINI_API_KEY="${GEMINI_API_KEY:-$GOOGLE_GENERATIVE_AI_API_KEY}"
    export GOOGLE_API_KEY="${GOOGLE_API_KEY:-$GOOGLE_GENERATIVE_AI_API_KEY}"
  fi
}

# ── 3. Attach RTK Repository ────────────────────────────────
attach_rtk() {
  if [[ "${ATTACH_RTK:-0}" =~ ^(1|true|yes|on)$ && ! -d rtk ]]; then
    echo "🔄 Attaching RTK repository..."
    git clone --depth 1 https://github.com/rtk-ai/rtk.git rtk || true
  fi
}

# ── 4. Smoke Test Mode ──────────────────────────────────────
run_smoke_test() {
  local target_name="$1"
  if [[ "${PROVEO_SMOKE_TEST:-0}" == "1" ]]; then
    echo "✅ PROVEO_SMOKE_READY ${PROVEO_SMOKE_TARGET:-$target_name}"
    exec sleep infinity
  fi
}

# ── 5. Ensure Node.js Dependencies ──────────────────────────
ensure_node_deps_common() {
  [[ -f package.json ]] || return 0
  [[ -d node_modules ]] && return 0

  # Check if directory is writable to avoid permission errors (e.g. root-owned parent directories)
  if [[ ! -w . ]]; then
    echo "🔎 Directory $(pwd) is not writable; skipping auto-install of dependencies."
    return 0
  fi

  echo "No node_modules found in $(pwd); installing dependencies..."
  if [[ -f pnpm-lock.yaml ]] || [[ -f pnpm-workspace.yaml ]] || ( [[ -f package.json ]] && grep -q '"workspace:' package.json 2>/dev/null ); then
    pnpm install
  elif [[ -f package-lock.json ]]; then
    npm ci
  else
    npm install
  fi
}

# ── 6. Tool Sourcing & Command Version Helpers ──────────────
# Cecli style command version check (fallback cmd [args])
command_version_cecli() {
  local fallback="$1"; shift
  timeout 5s "$@" 2>/dev/null || echo "$fallback"
}

# Opencode style command version check (cmd fallback [args])
command_version_opencode() {
  local name="$1"; shift
  local fallback="${1:-n/a}"; shift || true
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "$fallback"
    return 0
  fi
  timeout 5s "$name" "$@" 2>/dev/null || echo "$fallback"
}
