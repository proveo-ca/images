#!/usr/bin/env bash
# SPEC: _spec/defs/claudecode/claudecode-topology.puml, _spec/defs/claudecode/claudecode-egress-topology.puml, _spec/defs/claudecode/claudecode.paradigm.md
# Thin entrypoint: shared prelude via proveo-entrypoint (or bash fallback), then seed + exec.
set -e

if [[ -f /entrypoint-lib.sh ]]; then
  # shellcheck source=/dev/null
  source /entrypoint-lib.sh
fi

if command -v proveo-entrypoint >/dev/null 2>&1; then
  export PROVEO_SMOKE_TARGET=claudecode
  proveo-entrypoint prep claudecode || true
else
  ensure_runtime_user
  set_working_directory "/workspace"
  load_env
  bridge_git_identity /workspace/input
  report_git_context /workspace/input
  attach_rtk
  run_smoke_test "claudecode"
  ensure_project_tools
fi

# ── Verification command discovery ────────────────────────
# Prefer Go proveo-entrypoint verify; fall back to thin detect-verify.sh wrapper.
if command -v proveo-entrypoint >/dev/null 2>&1; then
  echo "── Verification Commands ────────────────────────────"
  proveo-entrypoint verify "$(pwd)" | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    printf '  %s\n' "$line"
  done
  echo "─────────────────────────────────────────────────────"
elif [[ -f /opt/proveo/lib/detect-verify.sh ]]; then
  # shellcheck source=/dev/null
  source /opt/proveo/lib/detect-verify.sh
  echo "── Verification Commands ────────────────────────────"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    printf '  %s\n' "$line"
  done < <(detect_verify_commands "$(pwd)")
  echo "─────────────────────────────────────────────────────"
fi

if [[ -f /opt/claudecode/defaults/CLAUDE.md && ! -f CLAUDE.md ]]; then
  cp /opt/claudecode/defaults/CLAUDE.md CLAUDE.md
  echo "🌱 Seeded CLAUDE.md into workspace"
fi

echo "Paradigm: ML blackbox algorithm (spec → plan → verify loop)"
[[ -n "${ENFORCEMENT_PROXY:-}" ]] && echo "🛡️  Enforcement proxy: ${ENFORCEMENT_PROXY}"
[[ -n "${INSPECT_PROXY:-}" && "${INSPECT_PROXY}" != "${ENFORCEMENT_PROXY:-}" ]] && echo "🔍  Inspection proxy: ${INSPECT_PROXY}"
[[ -n "${PROVEO_LOCAL_MODEL:-}" ]] && echo "🧠  Local model: ${PROVEO_LOCAL_MODEL}"

echo "🚀 Launching Claude Code..."
exec claude --dangerously-skip-permissions "$@"
