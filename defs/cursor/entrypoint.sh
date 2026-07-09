#!/usr/bin/env bash
# SPEC: _spec/defs/cursor/cursor-topology.puml, _spec/defs/cursor/cursor.paradigm.md
set -e

# Source shared entrypoint library if present
if [[ -f /entrypoint-lib.sh ]]; then
  source /entrypoint-lib.sh
fi

# ── Make the run-as UID usable (root-free) ─────────────────
# The wrapper runs us as the caller's host uid via `docker run --user`; give
# that uid a passwd entry and a writable HOME (shared across harnesses).
ensure_runtime_user

# ── Working directory ──────────────────────────────────────
set_working_directory "/app"

# ── Source .env file if present ────────────────────────────
load_env

# ── Environment Variable Bridge ────────────────────────────
# Standardized vars (see README.md):
#   ARCHITECT_MODEL -> CURSOR_MODEL (fallback: EDITOR_MODEL)
if [[ -z "${CURSOR_MODEL:-}" ]]; then
  if [[ -n "${ARCHITECT_MODEL:-}" ]]; then
    export CURSOR_MODEL="$ARCHITECT_MODEL"
  elif [[ -n "${EDITOR_MODEL:-}" ]]; then
    export CURSOR_MODEL="$EDITOR_MODEL"
  fi
fi

# ── Git identity from environment ──────────────────────────
# Bridge wrapper-forwarded GIT_* env into git's config-env so `git config --get`
# resolves file-free; repo-local identity stays authoritative.
bridge_git_identity

# ── Git context (repo / remote / identity / gh session) ────
report_git_context

# ── Optional: attach RTK repo ──────────────────────────────
attach_rtk

# ── Seed user-level defaults (~/.cursor) ────────────────────
# Only seed files that are missing, unless CURSOR_RESEED=1 forces a full
# re-seed. The mounted workspace is never touched here (see CURSOR_SEED_RULES).
CURSOR_HOME="${CURSOR_CONFIG_DIR:-$HOME/.cursor}"

seed_defaults() {
  local src="/opt/cursor/defaults"
  local dst="$CURSOR_HOME"
  mkdir -p "$dst" "$dst/agents"

  if [[ "${CURSOR_RESEED:-0}" == "1" ]]; then
    echo "🔁 CURSOR_RESEED=1 — re-seeding $dst from baked-in defaults"
    cp -f "$src/cli-config.json" "$dst/cli-config.json"
    if [[ -d "$src/agents" ]]; then
      for f in "$src/agents/"*.md; do
        [[ -e "$f" ]] || continue
        cp -f "$f" "$dst/agents/"
      done
    fi
    return 0
  fi

  local seeded=()
  [[ -f "$dst/cli-config.json" ]] || { cp "$src/cli-config.json" "$dst/cli-config.json"; seeded+=("cli-config.json"); }
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

# ── Proxy compatibility ─────────────────────────────────────
# Cursor's agent traffic uses HTTP/2 bidirectional streaming by default, which
# does not survive every proxy chain (Squid CONNECT + mitmproxy interception).
# Behind a proxy, force the documented HTTP/1.1 SSE fallback in the seeded
# config; the CLI's Node stack honors HTTP(S)_PROXY and NODE_EXTRA_CA_CERTS.
configure_proxy_compat() {
  [[ -n "${HTTP_PROXY:-}${HTTPS_PROXY:-}${http_proxy:-}${https_proxy:-}" ]] || return 0
  export NODE_USE_ENV_PROXY=1
  CONFIG_FILE="$CURSOR_HOME/cli-config.json" python3 - <<'PY'
import json, os
path = os.environ["CONFIG_FILE"]
try:
    with open(path, "r", encoding="utf-8") as fh:
        config = json.load(fh)
except Exception:
    config = {"version": 1}
# The shipped CLI nests this under "network" (the top-level spelling in older
# docs is dropped by its config normalizer).
network = config.get("network")
if not isinstance(network, dict):
    network = {}
    config["network"] = network
if network.get("useHttp1ForAgent") is not True:
    network["useHttp1ForAgent"] = True
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(config, fh, indent=2)
        fh.write("\n")
PY
  echo "🛡️  Proxy detected — set network.useHttp1ForAgent=true in $CURSOR_HOME/cli-config.json"
}
configure_proxy_compat

command_version() {
  command_version_opencode "$@"
}

echo "cursor cli version: $(command_version agent unknown --version)"
echo "Paradigm: policy-gated autonomous loop (spec → plan → implement → verify)"
echo "node version:       $(command_version node unknown --version)"
echo "pnpm version:       $(command_version pnpm n/a -v)"

# ── Policy layer report ────────────────────────────────────
echo "── Policy Layer ─────────────────────────────────────"
deny_count="$(CONFIG_FILE="$CURSOR_HOME/cli-config.json" python3 -c '
import json, os
try:
    with open(os.environ["CONFIG_FILE"], encoding="utf-8") as fh:
        print(len(json.load(fh).get("permissions", {}).get("deny", [])))
except Exception:
    print(0)
')"
echo "Deny rules (survive --force): ${deny_count} — $CURSOR_HOME/cli-config.json"
if [[ -f /etc/cursor/hooks.json ]]; then
  echo "Shell audit hook: /etc/cursor/hooks.json (enterprise layer, root-owned, fail-open)"
fi

# Surface available subagents (user + project)
agent_files=()
[[ -d "$CURSOR_HOME/agents" ]] && \
  while IFS= read -r f; do agent_files+=("$(basename "${f%.md}")"); done \
  < <(find "$CURSOR_HOME/agents" -maxdepth 1 -name '*.md' 2>/dev/null | sort)
[[ -d .cursor/agents ]] && \
  while IFS= read -r f; do agent_files+=("$(basename "${f%.md}") (project)"); done \
  < <(find .cursor/agents -maxdepth 1 -name '*.md' 2>/dev/null | sort)
if (( ${#agent_files[@]} > 0 )); then
  echo "🧑‍💻 Subagents available: ${agent_files[*]}"
fi
echo "─────────────────────────────────────────────────────"

# ── Steering files: detect and report, never write by default ──────────
# Project steering is the repo's own. The baked loop rule reaches the
# workspace only when explicitly requested with CURSOR_SEED_RULES=1.
report_steering() {
  echo "── Steering Files ───────────────────────────────────"
  local found=0
  [[ -f AGENTS.md ]] && { echo "✅ Found AGENTS.md"; found=1; }
  [[ -f CLAUDE.md ]] && { echo "✅ Found CLAUDE.md"; found=1; }
  [[ -f .cursorrules ]] && { echo "✅ Found .cursorrules (legacy)"; found=1; }
  if [[ -d .cursor/rules ]]; then
    local n
    n="$(find .cursor/rules -maxdepth 1 -name '*.mdc' 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$n" -gt 0 ]]; then
      echo "✅ Found .cursor/rules (${n} rule(s))"
      found=1
    fi
  fi

  if [[ "${CURSOR_SEED_RULES:-0}" == "1" ]]; then
    if mkdir -p .cursor/rules 2>/dev/null && \
       cp -f /opt/cursor/defaults/rules/proveo-loop.mdc .cursor/rules/proveo-loop.mdc 2>/dev/null; then
      echo "🌱 Seeded .cursor/rules/proveo-loop.mdc into workspace (CURSOR_SEED_RULES=1)"
    else
      echo "⚠️  CURSOR_SEED_RULES=1 but $(pwd) is not writable; skipping rule seed"
    fi
  elif (( found == 0 )); then
    echo "🔎 No steering files detected; seed the baked loop rule with CURSOR_SEED_RULES=1"
  fi
  echo "─────────────────────────────────────────────────────"
}
report_steering

# ── Verification command discovery ────────────────────────
if [[ -f /opt/proveo/lib/detect-verify.sh ]]; then
  # shellcheck source=/dev/null
  source /opt/proveo/lib/detect-verify.sh
  echo "── Verification Commands ────────────────────────────"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    cat <<< "  $line"
  done < <(detect_verify_commands "$(pwd)")
  echo "─────────────────────────────────────────────────────"
fi

# ── Smoke test mode ────────────────────────────────────────
run_smoke_test "cursor"

# ── Ensure node deps if this is a Node project ─────────────
ensure_node_deps_common
ensure_project_tools

# ── Auth check ─────────────────────────────────────────────
# All inference transits the Cursor backend; there is no provider-key or
# local-model alternative. Headless auth is CURSOR_API_KEY.
if [[ -z "${CURSOR_API_KEY:-}" ]]; then
  echo "⚠️  CURSOR_API_KEY not set. Create one at cursor.com/dashboard → API Keys,"
  echo "   or run 'agent login' interactively (NO_OPEN_BROWSER=1 prints the URL)."
  echo "   Login tokens live under ~/.cursor — persist them with a host mount if needed."
fi

# ── Launch ─────────────────────────────────────────────────
# Utility subcommands pass through without the autonomy flags.
case "${1:-}" in
  login|logout|status|whoami|ls|resume|update|upgrade|mcp|create-chat|uninstall|help|-v|--version|-h|--help)
    echo "🚀 Launching: agent $*"
    exec agent "$@"
    ;;
esac

# Full consent is intentional for the policy-gated autonomous loop: deny rules
# and the enterprise audit hook survive --force, and the container + egress
# layer is the outer boundary. Cursor's own OS sandbox is disabled — Docker is
# the sandbox (Landlock/seccomp inside a cap-dropped container is nondeterministic).
LAUNCH_ARGS=(--force --sandbox disabled)
if [[ -n "${CURSOR_MODEL:-}" ]]; then
  LAUNCH_ARGS+=(--model "$CURSOR_MODEL")
fi
for arg in "$@"; do
  if [[ "$arg" == "-p" || "$arg" == "--print" ]]; then
    # Headless runs need workspace trust up front (no prompt to answer).
    LAUNCH_ARGS+=(--trust)
    break
  fi
done

echo "🚀 Launching Cursor CLI: agent ${LAUNCH_ARGS[*]}"
exec agent "${LAUNCH_ARGS[@]}" "$@"
