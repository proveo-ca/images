#!/usr/bin/env bash
set -e

echo "curl version:       $(curl --version | head -n1)"
echo "npm version:        $(npm -v)"
echo "pnpm version:       $(pnpm -v)"
echo "playwright:         $(playwright --version)"

# ── Shared Aider flags ─────────────────────────────────────
common_flags="--no-gitignore"

launch() {
  local model="$1"        # e.g. gpt-4o-mini
  local key_flag="$2"     # e.g. --openai-api-key
  local key_val="$3"      # the actual key
  echo "🚀 Launching $model …"
  exec aider --model "$model" "$key_flag" "$key_val" $common_flags
}

# ── Auto-detect via env vars ───────────────────────────────
if [[ -n "$DEEPSEEK_API_KEY" ]]; then
  launch "deepseek-coder (DeepSeek)" "--openai-api-key" "$DEEPSEEK_API_KEY"
elif [[ -n "$ANTHROPIC_API_KEY" ]]; then
  launch "claude (Anthropic)" "--anthropic-api-key" "$ANTHROPIC_API_KEY"
elif [[ -n "$OPENAI_API_KEY" ]]; then
  launch "chatgpt (OpenAI" "--openai-api-key" "$OPENAI_API_KEY"
fi

# ── Manual fallback if no keys are set ─────────────────────
echo ""
echo "Choose LLM provider:"
echo "  1) chatgpt (OpenAI)"
echo "  2) claude (Anthropic)"
echo "  3) deepseek-coder (DeepSeek)"
read -rp "Selection? " provider_choice

case "$provider_choice" in
  1)
    read -srp "Enter OpenAI API key: " api_key; echo
    export OPENAI_API_KEY="$api_key"
    launch "chatgpt (OpenAI)" "--openai-api-key" "$api_key"
    ;;
  2)
    read -srp "Enter Anthropic API key: " api_key; echo
    export ANTHROPIC_API_KEY="$api_key"
    launch "sonnet" "--anthropic-api-key" "$api_key"
    ;;
  3)
    read -srp "Enter Deepseek API key: " api_key; echo
    export DEEPSEEK_API_KEY="$api_key"
    launch "deepseek-coder" "--openai-api-key" "$api_key"
    ;;
  *)
    echo "❌  Unrecognized option – aborting."
    exit 1
    ;;
esac
