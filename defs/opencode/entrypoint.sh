#!/usr/bin/env bash
set -e

# ── Working directory ──────────────────────────────────────
if [[ -d /app ]]; then
  cd /app
fi

# ── Source .env file if present ────────────────────────────
if [[ -f .env ]]; then
  set -a
  source .env
  set +a
  echo "✅ Loaded environment variables from .env"
fi

# ── Bridge common .env model aliases to opencode config vars ─────────
# opencode has one primary model slot here; prefer architect/planning model over editor model.
normalize_opencode_model() {
  local model="$1"
  [[ -n "$model" ]] || return 0

  if [[ "$model" == */* ]]; then
    printf '%s' "$model"
    return 0
  fi

  case "$model" in
    gpt-*|o[0-9]*|chatgpt-*) printf 'openai/%s' "$model" ;;
    claude-*) printf 'anthropic/%s' "$model" ;;
    grok-*) printf 'xai/%s' "$model" ;;
    gemini-*) printf 'google/%s' "$model" ;;
    deepseek-*) printf 'deepseek/%s' "$model" ;;
    *) printf '%s' "$model" ;;
  esac
}

if [[ -z "${OPENCODE_MODEL:-}" ]]; then
  if [[ -n "${ARCHITECT_MODEL:-}" ]]; then
    OPENCODE_MODEL="$(normalize_opencode_model "$ARCHITECT_MODEL")"
  elif [[ -n "${EDITOR_MODEL:-}" ]]; then
    OPENCODE_MODEL="$(normalize_opencode_model "$EDITOR_MODEL")"
  else
    OPENCODE_MODEL="anthropic/claude-sonnet-4-5"
  fi
  export OPENCODE_MODEL
fi

if [[ -z "${OPENCODE_SMALL_MODEL:-}" ]]; then
  if [[ -n "${EDITOR_MODEL:-}" ]]; then
    OPENCODE_SMALL_MODEL="$(normalize_opencode_model "$EDITOR_MODEL")"
  else
    OPENCODE_SMALL_MODEL="$(normalize_opencode_model "${SMALL_MODEL:-anthropic/claude-haiku-4-5}")"
  fi
  export OPENCODE_SMALL_MODEL
fi
# ── Seed global defaults (~/.config/opencode) ──────────────
# Only seed files that are missing, unless OPENCODE_RESEED=1 forces a full re-seed.
write_minimal_opencode_config() {
  local target="$1"
  cat >"$target" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {},
  "model": "{env:OPENCODE_MODEL}",
  "small_model": "{env:OPENCODE_SMALL_MODEL}",
  "autoupdate": false
}
EOF
}
seed_opencode_config() {
  local target="$1"
  local candidate
  local candidates=(
    "${HOME}/.config/opencode/sample_opencode.json"
    "${HOME}/Library/Application Support/opencode/sample_opencode.json"
    "/opt/opencode/sample_opencode.json"
    "/opt/homebrew/share/opencode/sample_opencode.json"
    "/usr/local/share/opencode/sample_opencode.json"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      cp -f "$candidate" "$target"
      return 0
    fi
  done

  write_minimal_opencode_config "$target"
}

seed_defaults() {
  local src="/opt/opencode/defaults"
  local dst="${HOME}/.config/opencode"
  mkdir -p "$dst" "$dst/agents"

  if [[ "${OPENCODE_RESEED:-0}" == "1" ]]; then
    echo "🔁 OPENCODE_RESEED=1 — re-seeding $dst from baked-in defaults"
    seed_opencode_config "$dst/opencode.json"
    if [[ -d "$src/agents" ]]; then
      for f in "$src/agents/"*.md; do
        [[ -e "$f" ]] || continue
        cp -f "$f" "$dst/agents/"
      done
    fi
    return 0
  fi

  local seeded=()
  [[ -f "$dst/opencode.json" ]] || { seed_opencode_config "$dst/opencode.json"; seeded+=("opencode.json"); }
  if [[ -d "$src/agents" ]]; then
    for f in "$src/agents/"*.md; do
      [[ -e "$f" ]] || continue
      local name; name="$(basename "$f")"
      [[ -f "$dst/agents/$name" ]] || { cp "$f" "$dst/agents/$name"; seeded+=("agents/$name"); }
    done
  fi
  if (( ${#seeded[@]} > 0 )); then
    echo "🌱 Seeded global defaults into $dst: ${seeded[*]}"
  fi
}
seed_defaults

command_version() {
  local name="$1"; shift
  local fallback="${1:-n/a}"; shift || true
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "$fallback"
    return 0
  fi
  timeout 5s "$name" "$@" 2>/dev/null || echo "$fallback"
}

echo "opencode version:   $(command_version opencode unknown --version)"
echo "node version:       $(command_version node unknown --version)"
echo "pnpm version:       $(command_version pnpm n/a -v)"

# ── Configuration check ────────────────────────────────────
echo "── Configuration Check ──────────────────────────────"
if [[ -f opencode.json ]]; then
  echo "✅ Found opencode.json"
elif [[ -f opencode.jsonc ]]; then
  echo "✅ Found opencode.jsonc"
else
  echo "🔎 No project opencode.json"
fi
if [[ -f AGENTS.md ]]; then echo "✅ Found AGENTS.md"; else echo "🔎 No AGENTS.md"; fi

# Surface available subagents (global + project)
agent_files=()
[[ -d "${HOME}/.config/opencode/agents" ]] && \
  while IFS= read -r f; do agent_files+=("@$(basename "${f%.md}")"); done \
  < <(find "${HOME}/.config/opencode/agents" -maxdepth 1 -name '*.md' 2>/dev/null | sort)
[[ -d .opencode/agents ]] && \
  while IFS= read -r f; do agent_files+=("@$(basename "${f%.md}") (project)"); done \
  < <(find .opencode/agents -maxdepth 1 -name '*.md' 2>/dev/null | sort)
if (( ${#agent_files[@]} > 0 )); then
  echo "🧑‍💻 Subagents available: ${agent_files[*]}"
fi
echo "─────────────────────────────────────────────────────"

# ── Ensure node deps if this is a Node project ─────────────
ensure_node_deps() {
  [[ -f package.json ]] || return
  [[ -d node_modules ]] && return
  echo "No node_modules found in $(pwd); installing dependencies..."
  if [[ -f pnpm-lock.yaml ]]; then
    pnpm install
  elif [[ -f package-lock.json ]]; then
    npm ci
  else
    npm install
  fi
}
ensure_node_deps

# ── API key detection ──────────────────────────────────────
has_api_key() {
  [[ -n "$ANTHROPIC_API_KEY" ]] || \
  [[ -n "$OPENAI_API_KEY" ]] || \
  [[ -n "$OPENROUTER_API_KEY" ]] || \
  [[ -n "$XAI_API_KEY" ]] || \
  [[ -n "$GEMINI_API_KEY" ]] || \
  [[ -n "$GOOGLE_API_KEY" ]] || \
  [[ -n "$DEEPSEEK_API_KEY" ]] || \
  [[ -n "$GROQ_API_KEY" ]] || \
  [[ -n "$MISTRAL_API_KEY" ]]
}

has_project_config() {
  [[ -f opencode.json ]] || [[ -f opencode.jsonc ]]
}

if ! has_api_key && ! has_project_config; then
  echo "⚠️  No provider API key env vars and no opencode.json detected."
  echo "   Set one of: ANTHROPIC_API_KEY, OPENAI_API_KEY, OPENROUTER_API_KEY,"
  echo "   XAI_API_KEY, GEMINI_API_KEY, DEEPSEEK_API_KEY, GROQ_API_KEY, ..."
  echo "   Or run 'opencode auth login' to configure credentials interactively."
fi

# ── Launch ─────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
  echo "🚀 Launching: opencode $*"
  exec opencode "$@"
fi

echo "🚀 Launching opencode TUI..."
exec opencode
