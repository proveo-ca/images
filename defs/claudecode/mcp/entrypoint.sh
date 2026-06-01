#!/usr/bin/env bash
set -e

# ── Working directory ──────────────────────────────────────
if [[ -d /workspace ]]; then
  cd /workspace
fi

# ── Source .env file if present ────────────────────────────
if [[ -f .env ]]; then
  echo "✅ Found .env"
  set -a
  source .env
  set +a
  echo "✅ Loaded environment variables from .env"
else
  echo "🔎 No .env found"
fi

# ── Optional: attach RTK repo ──────────────────────────────
if [[ "${ATTACH_RTK:-0}" =~ ^(1|true|yes|on)$ && ! -d rtk ]]; then
  git clone --depth 1 https://github.com/rtk-ai/rtk.git rtk || true
fi

# ── Smoke test mode ────────────────────────────────────────
if [[ "${PROVEO_SMOKE_TEST:-0}" == "1" ]]; then
  echo "✅ PROVEO_SMOKE_READY ${PROVEO_SMOKE_TARGET:-claudecode}"
  exec sleep infinity
fi

# ── Launch Claude Code ─────────────────────────────────────
echo "🚀 Launching Claude Code..."
exec claude --dangerously-skip-permissions "$@"
