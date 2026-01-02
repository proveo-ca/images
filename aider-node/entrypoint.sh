#!/usr/bin/env bash
set -e

# Always use /app as the working directory if it exists
if [[ -d /app ]]; then
  cd /app
fi

# ── Source .env file if present ────────────────────────────
if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

echo "curl version:       $(curl --version | head -n1)"
echo "npm version:        $(npm -v)"
echo "pnpm version:       $(pnpm -v)"
echo "playwright:         $(playwright --version)"

ensure_node_deps() {
  # Only attempt installs if we're in a Node project
  if [[ ! -f package.json ]]; then
    return
  fi

  # If node_modules already exists, assume deps are installed
  if [[ -d node_modules ]]; then
    return
  fi

  echo "No node_modules found in $(pwd); installing dependencies..."

  if [[ -f pnpm-lock.yaml ]]; then
    pnpm install
  elif [[ -f package-lock.json ]]; then
    npm ci
  else
    npm install
  fi
}

# Ensure project deps are installed if we're in a Node project
ensure_node_deps

# ── Shared Aider flags ─────────────────────────────────────
common_flags="--no-gitignore"

# ── Check if aider config exists ───────────────────────────
has_aider_config() {
  [[ -f .aider.conf.yml ]] || [[ -f .aider.conf.yaml ]] || [[ -f .aiderrc ]]
}

# ── Check if any API key is set ────────────────────────────
has_api_key() {
  [[ -n "$XAI_API_KEY" ]] || \
  [[ -n "$DEEPSEEK_API_KEY" ]] || \
  [[ -n "$ANTHROPIC_API_KEY" ]] || \
  [[ -n "$OPENAI_API_KEY" ]] || \
  [[ -n "$GEMINI_API_KEY" ]] || \
  [[ -n "$OPENROUTER_API_KEY" ]]
}

# ── Launch aider directly if config exists ─────────────────
if has_aider_config; then
  echo "🚀 Launching aider with detected config..."
  exec aider $common_flags
fi

# ── Launch aider directly if AIDER_MODEL is set ────────────
if [[ -n "$AIDER_MODEL" ]]; then
  echo "🚀 Launching with AIDER_MODEL=$AIDER_MODEL ..."
  exec aider $common_flags
fi

# ── Launch with specific model and key ─────────────────────
launch() {
  local model="$1"        # e.g. openai/gpt-5.2
  local key_flag="$2"     # e.g. --openai-api-key
  local key_val="$3"      # the actual key
  
  local cmd=("aider" "--model" "$model" $common_flags)
  
  if [[ -n "$key_flag" && -n "$key_val" ]]; then
    cmd+=("$key_flag" "$key_val")
  fi

  echo "🚀 Launching ${cmd[*]} …"
  exec "${cmd[@]}"
}

get_latest_model_for_provider() {
  local provider="$1"
  local models_output
  models_output=$(aider --list-models - 2>/dev/null || echo "")

  case "$provider" in
    "xai")
      echo "$models_output" | grep -E "^- xai/grok-4" | head -1 | sed 's/^- //' || echo "grok-4-latest"
      ;;
    "deepseek")
      echo "$models_output" | grep -E "^- (deepseek/deepseek-r1|deepseek/deepseek-v3)" | head -1 | sed 's/^- //' || echo "deepseek"
      ;;
    "anthropic")
      echo "$models_output" | grep -E "^- (claude-opus-4-5|claude-sonnet-4-5)" | head -1 | sed 's/^- //' || echo "opus"
      ;;
    "openai")
      echo "$models_output" | grep -E "^- (gpt-5.2-pro)" | head -1 | sed 's/^- //' || echo "chatgpt"
      ;;
    "google")
      echo "$models_output" | grep -E "^- (gemini/gemini-3-pro-preview)" | head -1 | sed 's/^- //' || echo "gemini"
      ;;
    "openrouter")
      echo "$models_output" | grep -E "^- openrouter/openrouter/(quasar|optimus)" | head -1 | sed 's/^- //' || echo "quasar"
      ;;
  esac
}

get_latest_models() {
  echo "Fetching latest available models..."
  local models_output
  models_output=$(aider --list-models - 2>/dev/null || echo "")

  if [[ -z "$models_output" ]]; then
    echo "❌ Could not fetch model list"
    return 1
  fi

  echo "Available models (showing popular ones):"
  echo "─────────────────────────────────────"

  # Extract and display popular models by provider
  echo "XAI/Grok models:"
  echo "$models_output" | grep -E "^- xai/grok-" | head -5

  echo ""
  echo "OpenAI models:"
  echo "$models_output" | grep -E "^- (openai/gpt-)" | head -5

  echo ""
  echo "Anthropic models:"
  echo "$models_output" | grep -E "^- (claude-|anthropic/)" | head -5

  echo ""
  echo "DeepSeek models:"
  echo "$models_output" | grep -E "^- (deepseek|deepseek/)" | head -3

  echo ""
  echo "Google models:"
  echo "$models_output" | grep -E "^- (gemini|gemini/)" | head -5
}

# ── Auto-detect via env vars (no config file) ──────────────
if [[ -n "$GEMINI_API_KEY" ]]; then
  latest_model=$(get_latest_model_for_provider "google")
  launch "$latest_model" "" ""
elif [[ -n "$ANTHROPIC_API_KEY" ]]; then
  latest_model=$(get_latest_model_for_provider "anthropic")
  launch "$latest_model" "--anthropic-api-key" "$ANTHROPIC_API_KEY"
elif [[ -n "$XAI_API_KEY" ]]; then
  latest_model=$(get_latest_model_for_provider "xai")
  launch "$latest_model" "--openai-api-key" "$XAI_API_KEY"
elif [[ -n "$DEEPSEEK_API_KEY" ]]; then
  latest_model=$(get_latest_model_for_provider "deepseek")
  launch "$latest_model" "--openai-api-key" "$DEEPSEEK_API_KEY"
elif [[ -n "$OPENAI_API_KEY" ]]; then
  latest_model=$(get_latest_model_for_provider "openai")
  launch "$latest_model" "--openai-api-key" "$OPENAI_API_KEY"
elif [[ -n "$OPENROUTER_API_KEY" ]]; then
  latest_model=$(get_latest_model_for_provider "openrouter")
  launch "$latest_model" "--openai-api-key" "$OPENROUTER_API_KEY"
fi

# ── Manual fallback if no keys are set ─────────────────────
echo ""
echo "Choose LLM provider:"
echo "  1) Gemini (Google) - gemini-3-pro-preview"
echo "  2) ChatGPT (OpenAI) - gpt-5.2"
echo "  3) Claude (Anthropic) - claude-opus-4-5"
echo "  4) Grok (X.AI) - xai/grok-4"
echo "  5) DeepSeek - DeepSeek Chat"
echo "  6) OpenRouter - Quasar Alpha"
echo "  7) Other - Show all available models"
read -rp "Selection? " provider_choice

case "$provider_choice" in
  1)
    read -srp "Enter Gemini API key: " api_key; echo
    export GEMINI_API_KEY="$api_key"
    launch "gemini/gemini-3-pro-preview" "" ""
    ;;
  2)
    read -srp "Enter OpenAI API key: " api_key; echo
    export OPENAI_API_KEY="$api_key"
    launch "gpt-5.2" "--openai-api-key" "$api_key"
    ;;
  3)
    read -srp "Enter Anthropic API key: " api_key; echo
    export ANTHROPIC_API_KEY="$api_key"
    launch "claude-opus-4-5" "--anthropic-api-key" "$api_key"
    ;;
  4)
    read -srp "Enter xAI API key: " api_key; echo
    export XAI_API_KEY="$api_key"
    launch "xai/grok-4" "--openai-api-key" "$api_key"
    ;;
  5)
    read -srp "Enter DeepSeek API key: " api_key; echo
    export DEEPSEEK_API_KEY="$api_key"
    launch "deepseek" "--openai-api-key" "$api_key"
    ;;
  6)
    read -srp "Enter OpenRouter API key: " api_key; echo
    export OPENROUTER_API_KEY="$api_key"
    launch "openrouter/auto" "--openai-api-key" "$api_key"
    ;;
  7)
    get_latest_models
    echo ""
    echo "Model aliases (shortcuts):"
    echo "  • opus    - Claude Opus"
    echo "  • gpt-5.2    - OpenAI GPT-5.2"
    echo "  • grok-4-latest - xAI Grok 4"
    echo "  • gemini    - Google Gemini"
    echo "  • deepseek  - DeepSeek"
    echo ""
    read -rp "Enter model alias or full model name: " model_choice
    echo ""

    # Determine which API key to ask for based on model choice
     if [[ "$model_choice" =~ ^(sonnet|haiku|opus|claude) ]]; then
       read -srp "Enter Anthropic API key: " api_key; echo
       launch "$model_choice" "--anthropic-api-key" "$api_key"
     elif [[ "$model_choice" =~ ^(grok|xai/|grok-4) ]]; then
       read -srp "Enter X.AI API key: " api_key; echo
       launch "$model_choice" "--openai-api-key" "$api_key"
     elif [[ "$model_choice" =~ ^(gpt) ]]; then
       read -srp "Enter OpenAI API key: " api_key; echo
       launch "$model_choice" "--openai-api-key" "$api_key"
     elif [[ "$model_choice" =~ ^(gemini|flash) ]]; then
       read -srp "Enter Google API key: " api_key; echo
       export GEMINI_API_KEY="$api_key"
       launch "$model_choice" "" ""
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
    echo "❌ Unrecognized option – aborting."
    exit 1
    ;;
esac
