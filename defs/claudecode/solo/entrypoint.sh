#!/usr/bin/env bash
# SPEC: _spec/defs/claudecode/claudecode-topology.puml, _spec/defs/claudecode/claudecode-egress-topology.puml, _spec/defs/claudecode/claudecode.paradigm.md
set -e

# Source shared entrypoint library if present
if [[ -f /entrypoint-lib.sh ]]; then
  source /entrypoint-lib.sh
fi

# ── Working directory ──────────────────────────────────────
set_working_directory "/workspace"

# ── Source .env file if present ────────────────────────────
load_env

# ── Optional: attach RTK repo ──────────────────────────────
attach_rtk

# ── Smoke test mode ────────────────────────────────────────
run_smoke_test "claudecode"

# ── Ensure project-level tools (nx, turbo, mise) ───────────
ensure_project_tools

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

# ── Seed project-level CLAUDE.md if missing ───────────────
if [[ -f /opt/claudecode/defaults/CLAUDE.md && ! -f CLAUDE.md ]]; then
  cp /opt/claudecode/defaults/CLAUDE.md CLAUDE.md
  echo "🌱 Seeded CLAUDE.md into workspace"
fi

# ── Launch Claude Code ─────────────────────────────────────
echo "Paradigm: ML blackbox algorithm (spec → plan → verify loop)"

if [[ -n "${ENFORCEMENT_PROXY:-}" ]]; then
  echo "🛡️  Enforcement proxy: ${ENFORCEMENT_PROXY}"
elif [[ -n "${HTTP_PROXY:-}" || -n "${HTTPS_PROXY:-}" ]]; then
  echo "🛡️  Outbound proxy active: ${HTTP_PROXY:-${HTTPS_PROXY}}"
fi
if [[ -n "${INSPECT_PROXY:-}" && "${INSPECT_PROXY}" != "${ENFORCEMENT_PROXY:-}" ]]; then
  echo "🔍  Inspection proxy (mitmproxy): ${INSPECT_PROXY}"
fi
if [[ -n "${PROVEO_EGRESS_CA_CERT:-}" && -f "${PROVEO_EGRESS_CA_CERT}" ]]; then
  echo "🔐  Trusting mitmproxy CA for HTTPS inspection: ${PROVEO_EGRESS_CA_CERT}"
fi
if [[ -n "${PROVEO_LOCAL_MODEL:-}" ]]; then
  echo "🧠  Local model: ${PROVEO_LOCAL_MODEL} via ${OLLAMA_API_BASE:-http://ollama:11434} (NO_PROXY bypass)"
fi

echo "🚀 Launching Claude Code..."

# Full consent is intentional for the ML blackbox loop.
# The container sandbox is the security boundary.
exec claude --dangerously-skip-permissions "$@"
