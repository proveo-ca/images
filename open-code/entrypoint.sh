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

# ── Seed global defaults (~/.config/opencode) ──────────────
# Only seed files that are missing, unless OPENCODE_RESEED=1 forces a full re-seed.
seed_defaults() {
  local src="/opt/opencode/defaults"
  local dst="${HOME}/.config/opencode"
  [[ -d "$src" ]] || return 0
  mkdir -p "$dst" "$dst/agents"

  if [[ "${OPENCODE_RESEED:-0}" == "1" ]]; then
    echo "🔁 OPENCODE_RESEED=1 — re-seeding $dst from baked-in defaults"
    cp -f "$src/opencode.json" "$dst/opencode.json"
    cp -f "$src/agents/"*.md "$dst/agents/"
    return 0
  fi

  local seeded=()
  [[ -f "$dst/opencode.json" ]] || { cp "$src/opencode.json" "$dst/opencode.json"; seeded+=("opencode.json"); }
  for f in "$src/agents/"*.md; do
    local name; name="$(basename "$f")"
    [[ -f "$dst/agents/$name" ]] || { cp "$f" "$dst/agents/$name"; seeded+=("agents/$name"); }
  done
  if (( ${#seeded[@]} > 0 )); then
    echo "🌱 Seeded global defaults into $dst: ${seeded[*]}"
  fi
}
seed_defaults

echo "opencode version:   $(opencode --version 2>/dev/null || echo unknown)"
echo "node version:       $(node --version)"
echo "pnpm version:       $(pnpm -v 2>/dev/null || echo n/a)"

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
