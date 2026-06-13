#!/usr/bin/env bash
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

# ── Launch Claude Code ─────────────────────────────────────
echo "🚀 Launching Claude Code..."
exec claude --dangerously-skip-permissions "$@"
