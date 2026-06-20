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
    echo "✅ Found .env at $env_path"
    set -a
    source "$env_path"
    set +a
    echo "✅ Loaded environment variables from .env"
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
    if [[ ! -w . ]]; then
      echo "⚠️  Current directory $(pwd) is not writable; skipping RTK attachment."
      return 0
    fi
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
  # An explicit lockfile is authoritative — honor it before falling back to
  # the pnpm workspace heuristic (which would otherwise hijack yarn/npm
  # monorepos that happen to use the "workspace:" dependency protocol).
  if [[ -f pnpm-lock.yaml ]]; then
    pnpm install
  elif [[ -f package-lock.json ]]; then
    npm ci
  elif [[ -f yarn.lock ]]; then
    if command -v yarn >/dev/null 2>&1; then yarn install; else npm install; fi
  elif [[ -f pnpm-workspace.yaml ]] || \
       ( grep -q '"packageManager": *"[^"]*pnpm' package.json 2>/dev/null ) || \
       ( find . -maxdepth 4 -name package.json -not -path '*/node_modules/*' -not -path '*/.*/*' -exec grep -q '"workspace:' {} + 2>/dev/null ); then
    pnpm install
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

# ── 7. Declarative Env Var Bridges Mapping ──────────────────
apply_env_bridges() {
  local eval_cmds
  eval_cmds=$(python3 - <<'PY'
import json
import os
import re
import shlex

# Order matters: a bridge whose "default" references "$VAR" sees values
# resolved by earlier bridges (we feed each resolved export back into the
# environment below), so bridges that depend on OPENCODE_MODEL / the small
# model must come after the bridges that produce them.
bridges_json = """[
  { "from": "ARCHITECT_MODEL", "to": "OPENCODE_MODEL", "fallback": "EDITOR_MODEL", "default": "anthropic/claude-sonnet-4-5", "transform": "normalize" },
  { "from": "EDITOR_MODEL", "to": "OPENCODE_BUILD_MODEL", "default": "$OPENCODE_MODEL", "transform": "normalize" },
  { "from": "EDITOR_MODEL", "to": "OPENCODE_SMALL_MODEL", "fallback": "SMALL_MODEL", "default": "anthropic/claude-haiku-4-5", "transform": "normalize" },
  { "from": "OPENCODE_SMALL_MODEL", "to": "SMALL_MODEL", "transform": "normalize" },
  { "from": "GEMINI_API_KEY", "to": "GOOGLE_GENERATIVE_AI_API_KEY" },
  { "from": "GOOGLE_API_KEY", "to": "GOOGLE_GENERATIVE_AI_API_KEY" }
]"""

def normalize_model(model):
    if not model:
        return ""
    if "/" in model:
        return model
    model_lower = model.lower()
    # OpenAI reasoning models are any "o" followed by a digit (o1, o3, o4-mini, ...)
    if model_lower.startswith("gpt-") or model_lower.startswith("chatgpt-") or re.match(r"o[0-9]", model_lower):
        return f"openai/{model}"
    elif model_lower.startswith("claude-"):
        return f"anthropic/{model}"
    elif model_lower.startswith("grok-"):
        return f"xai/{model}"
    elif model_lower.startswith("gemini-"):
        return f"google/{model}"
    elif model_lower.startswith("deepseek-"):
        return f"deepseek/{model}"
    return model

bridges = json.loads(bridges_json)
for bridge in bridges:
    # Skip if target already explicitly defined in environment
    if bridge["to"] in os.environ:
        continue

    src_val = os.environ.get(bridge["from"], "")

    # Check fallback if src is empty
    if not src_val and "fallback" in bridge:
        src_val = os.environ.get(bridge["fallback"], "")

    # Check default if still empty
    if not src_val and "default" in bridge:
        d = bridge["default"]
        if d.startswith("$"):
            ref_var = d[1:]
            src_val = os.environ.get(ref_var, "")
        else:
            src_val = d

    if src_val:
        # Apply transformation if specified
        if bridge.get("transform") == "normalize":
            src_val = normalize_model(src_val)

        target_var = bridge["to"]
        # Feed the resolved value back so later "$VAR" defaults can see it.
        os.environ[target_var] = src_val
        # Emit a shell-safe assignment (shlex.quote prevents the eval below
        # from performing expansion or command substitution on the value).
        print(f"export {target_var}={shlex.quote(src_val)}")
PY
)
  eval "$eval_cmds"

  # Ensure OPENCODE_SMALL_MODEL matches SMALL_MODEL for consistency
  if [[ -z "${OPENCODE_SMALL_MODEL:-}" && -n "${SMALL_MODEL:-}" ]]; then
    export OPENCODE_SMALL_MODEL="$SMALL_MODEL"
  fi
}

# ── 8. Automatic Project-Level Tools Installer ──────────────
ensure_project_tools() {
  # Opt-out: accept the common falsy spellings, case-insensitively. In
  # locked-egress deployments (no outbound network) this should be disabled so
  # startup never blocks on a registry/CDN fetch.
  case "$(printf '%s' "${PROVEO_AUTO_INSTALL_TOOLS:-true}" | tr '[:upper:]' '[:lower:]')" in
    false|0|no|off|disable|disabled) return 0 ;;
  esac

  # Bounded network so a blackholed egress can't hang the container at startup.
  local -a npm_net=(--fetch-timeout=60000 --fetch-retries=1)

  # Add user-local bin to PATH for prefix-based installations
  mkdir -p "${HOME}/.local/bin"
  export PATH="${HOME}/.local/bin:${PATH}"

  # 1. NX Detection & Installation
  if [[ -f nx.json ]]; then
    if ! command -v nx >/dev/null 2>&1; then
      echo "📦 Detected nx.json. Dynamically installing nx..."
      npm install -g "${npm_net[@]}" --prefix "${HOME}/.local" nx@latest || echo "⚠️ Failed to dynamically install nx"
    fi
  fi

  # 2. Turbo Detection & Installation
  if [[ -f turbo.json ]]; then
    if ! command -v turbo >/dev/null 2>&1; then
      echo "📦 Detected turbo.json. Dynamically installing turbo..."
      npm install -g "${npm_net[@]}" --prefix "${HOME}/.local" turbo@latest || echo "⚠️ Failed to dynamically install turbo"
    fi
  fi

  # 3. Mise Detection & Installation
  if [[ -f mise.toml || -f mise.local.toml || -f .mise.toml || -f .mise.local.toml || -d mise || -d .mise || -f .tool-versions ]]; then
    if ! command -v mise >/dev/null 2>&1; then
      echo "📦 Detected mise config or .tool-versions. Dynamically installing mise..."
      # Download first so a blocked/timed-out fetch is detected via curl's own
      # exit status (piping straight to sh masks it: an empty body exits 0).
      local mise_installer
      mise_installer="$(mktemp)"
      if curl -fsSL --connect-timeout 5 --max-time 120 https://mise.run -o "$mise_installer"; then
        MISE_INSTALL_PATH="${HOME}/.local/bin/mise" sh "$mise_installer" || echo "⚠️ mise install script failed"
      else
        npm install -g "${npm_net[@]}" --prefix "${HOME}/.local" @jdx/mise@latest || echo "⚠️ Failed to dynamically install mise"
      fi
      rm -f "$mise_installer"
    fi
  fi
}
