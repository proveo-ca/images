#!/usr/bin/env bash
set -e

# ── Shared Aider flags ─────────────────────────────────────
common_flags="--no-gitignore --subtree-only"

launch() {
  local model="$1"        # e.g. gpt-4o-mini
  local key_flag="$2"     # e.g. --openai-api-key
  local key_val="$3"      # the actual key
  echo "🚀 Launching $model …"
  exec aider --model "$model" "$key_flag" "$key_val" $common_flags
}

# ── Auto-detect via env vars ───────────────────────────────
if [[ -n "$DEEPSEEK_API_KEY" ]]; then
  launch "deepseek-coder:6.7b" "--openai-api-key" "$DEEPSEEK_API_KEY"
elif [[ -n "$ANTHROPIC_API_KEY" ]]; then
  launch "sonnet" "--anthropic-api-key" "$ANTHROPIC_API_KEY"
elif [[ -n "$OPENAI_API_KEY" ]]; then
  launch "gpt-4o-mini" "--openai-api-key" "$OPENAI_API_KEY"
fi

# ── Manual fallback if no keys are set ─────────────────────
echo ""
echo "Choose LLM provider:"
echo "  1) OpenAI (gpt-4o-mini)"
echo "  2) Anthropic (sonnet)"
echo "  3) Deepseek (deepseek-coder:6.7b)"
read -rp "Selection? " provider_choice

case "$provider_choice" in
  1)
    read -srp "Enter OpenAI API key: " api_key; echo
    launch "gpt-4o-mini" "--openai-api-key" "$api_key"
    ;;
  2)
    read -srp "Enter Anthropic API key: " api_key; echo
    launch "sonnet" "--anthropic-api-key" "$api_key"
    ;;
  3)
    read -srp "Enter Deepseek API key: " api_key; echo
    launch "deepseek-coder:6.7b" "--openai-api-key" "$api_key"
    ;;
  *)
    echo "❌  Unrecognized option – aborting."
    exit 1
    ;;
esac
