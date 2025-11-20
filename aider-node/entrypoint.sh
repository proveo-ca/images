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
if [[ -n "$XAI_API_KEY" ]]; then
  launch "grok4" "--openai-api-key" "$XAI_API_KEY"
elif [[ -n "$DEEPSEEK_API_KEY" ]]; then
  launch "deepseek" "--openai-api-key" "$DEEPSEEK_API_KEY"
elif [[ -n "$ANTHROPIC_API_KEY" ]]; then
  launch "sonnet" "--anthropic-api-key" "$ANTHROPIC_API_KEY"
elif [[ -n "$OPENAI_API_KEY" ]]; then
  launch "4o-2024-08-06" "--openai-api-key" "$OPENAI_API_KEY"
elif [[ -n "$GOOGLE_API_KEY" ]]; then
  launch "gemini" "--openai-api-key" "$GOOGLE_API_KEY"
elif [[ -n "$OPENROUTER_API_KEY" ]]; then
  launch "quasar" "--openai-api-key" "$OPENROUTER_API_KEY"
fi

# ── Manual fallback if no keys are set ─────────────────────
echo ""
echo "Choose LLM provider:"
echo "  1) Grok (X.AI) - Latest Grok 4"
echo "  2) ChatGPT (OpenAI) - GPT-4o (2024-08-06)"
echo "  3) Claude (Anthropic) - Sonnet 4"
echo "  4) DeepSeek - DeepSeek Chat"
echo "  5) Gemini (Google) - Gemini 2.5 Pro"
echo "  6) OpenRouter - Quasar Alpha"
echo "  7) Other - Show all available models"
read -rp "Selection? " provider_choice

case "$provider_choice" in
  1)
    read -srp "Enter X.AI API key: " api_key; echo
    export XAI_API_KEY="$api_key"
    launch "grok4" "--openai-api-key" "$api_key"
    ;;
  2)
    read -srp "Enter OpenAI API key: " api_key; echo
    export OPENAI_API_KEY="$api_key"
    launch "4o-2024-08-06" "--openai-api-key" "$api_key"
    ;;
  3)
    read -srp "Enter Anthropic API key: " api_key; echo
    export ANTHROPIC_API_KEY="$api_key"
    launch "sonnet" "--anthropic-api-key" "$api_key"
    ;;
  4)
    read -srp "Enter DeepSeek API key: " api_key; echo
    export DEEPSEEK_API_KEY="$api_key"
    launch "deepseek" "--openai-api-key" "$api_key"
    ;;
  5)
    read -srp "Enter Google API key: " api_key; echo
    export GOOGLE_API_KEY="$api_key"
    launch "gemini" "--openai-api-key" "$api_key"
    ;;
  6)
    read -srp "Enter OpenRouter API key: " api_key; echo
    export OPENROUTER_API_KEY="$api_key"
    launch "quasar" "--openai-api-key" "$api_key"
    ;;
  7)
    echo ""
    echo "Available model aliases from Aider:"
    echo "─────────────────────────────────────"
    echo "Claude models:"
    echo "  • sonnet    - claude-sonnet-4-20250514 (latest)"
    echo "  • haiku     - claude-3-5-haiku-20241022"
    echo "  • opus      - claude-opus-4-20250514"
    echo ""
    echo "GPT models:"
    echo "  • 4o        - gpt-4o-2024-08-06"
    echo "  • 4         - gpt-4-0613"
    echo "  • 4-turbo   - gpt-4-1106-preview"
    echo "  • 35turbo   - gpt-3.5-turbo"
    echo ""
    echo "Other models:"
    echo "  • grok4     - xai/grok-4-latest"
    echo "  • deepseek  - deepseek/deepseek-chat"
    echo "  • r1        - deepseek/deepseek-reasoner"
    echo "  • gemini    - gemini/gemini-2.5-pro"
    echo "  • flash     - gemini/gemini-2.5-flash"
    echo "  • quasar    - openrouter/openrouter/quasar-alpha"
    echo "  • optimus   - openrouter/openrouter/optimus-alpha"
    echo ""
    read -rp "Enter model alias or full model name: " model_choice
    echo ""
    
    # Determine which API key to ask for based on model choice
    if [[ "$model_choice" =~ ^(sonnet|haiku|opus|claude) ]]; then
      read -srp "Enter Anthropic API key: " api_key; echo
      launch "$model_choice" "--anthropic-api-key" "$api_key"
    elif [[ "$model_choice" =~ ^(grok|xai/) ]]; then
      read -srp "Enter X.AI API key: " api_key; echo
      launch "$model_choice" "--openai-api-key" "$api_key"
    elif [[ "$model_choice" =~ ^(deepseek|r1) ]]; then
      read -srp "Enter DeepSeek API key: " api_key; echo
      launch "$model_choice" "--openai-api-key" "$api_key"
    elif [[ "$model_choice" =~ ^(gemini|flash) ]]; then
      read -srp "Enter Google API key: " api_key; echo
      launch "$model_choice" "--openai-api-key" "$api_key"
    elif [[ "$model_choice" =~ ^(quasar|optimus|openrouter/) ]]; then
      read -srp "Enter OpenRouter API key: " api_key; echo
      launch "$model_choice" "--openai-api-key" "$api_key"
    else
      # Default to OpenAI for unknown models
      read -srp "Enter OpenAI API key: " api_key; echo
      launch "$model_choice" "--openai-api-key" "$api_key"
    fi
    ;;
  *)
    echo "❌  Unrecognized option – aborting."
    exit 1
    ;;
esac
