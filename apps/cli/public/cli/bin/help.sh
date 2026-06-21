#!/usr/bin/env bash
set -euo pipefail

HELP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HELP_SCRIPT_DIR/proveo"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  CYAN=$'\033[36m'
  BLUE=$'\033[34m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  RESET=$'\033[0m'
else
  BOLD=""
  DIM=""
  CYAN=""
  BLUE=""
  GREEN=""
  YELLOW=""
  RESET=""
fi

printf '\n%s%s' "$BOLD" "$CYAN"
cat <<'EOF'
        ┌───────●                        ───────┐
        │                                       │
        │      pr●veo                           │
        │                S O L U T I O N S      │
        │                                       │
        └───────                         ●──────┘
EOF
printf '%s\n' "$RESET"
printf '  %scontainerized AI engineering harnesses%s\n' "$DIM" "$RESET"
printf '\n'

printf '  %s%sCommands%s\n' "$BOLD" "$YELLOW" "$RESET"
printf '    %-34s %s\n' "proveo help" "Show this help text"
printf '    %-34s %s\n' "proveo init" "Create a .env from host API keys"
printf '    %-34s %s\n' "proveo list" "List supported container targets"
printf '    %-34s %s\n' "proveo run <target> [-- <args...>]" "Run a container target"
printf '    %-34s %s\n' "proveo uninstall" "Remove proveo from PATH"
printf '    %-34s %s\n' "proveo version" "Show version details"
printf '\n'

printf '  %s%sTargets%s\n' "$BOLD" "$YELLOW" "$RESET"
for target in "${TARGETS[@]}"; do
  printf '    %-18s %s\n' "$target" "$(target_description "$target")"
done
printf '\n'

printf '  %s%sNetwork Security — egress modes (claudecode)%s\n' "$BOLD" "$YELLOW" "$RESET"
printf '    %-34s %s\n' "--egress-mode open" "Direct internet on the default bridge (default)"
printf '    %-34s %s\n' "--egress-mode proxy" "Squid enforcement; HTTP/HTTPS only, non-web blocked"
printf '    %-34s %s\n' "--egress-mode inspected-firewall" "mitmproxy HTTPS inspection upstream of Squid"
printf '\n'

printf '  %s%sRun options (claudecode)%s\n' "$BOLD" "$YELLOW" "$RESET"
printf '    %-34s %s\n' "--local-model NAME" "Assign an Ollama local model (e.g. gemma4) via a sidecar;"
printf '    %-34s %s\n' "" "calls bypass the egress proxy, all else stays policed"
printf '    %-34s %s\n' "--input-dir PATH" "Directory to mount as input (default: current dir)"
printf '    %-34s %s\n' "--output-dir PATH" "Directory to mount as output (default: ./reports)"
printf '    %-34s %s\n' "--data-dir PATH" "Optional reference data, mounted read-only"
printf '    %-34s %s\n' "--shell" "Open a shell in the container instead of the harness"
printf '\n'

printf '  %s%sExamples%s\n' "$BOLD" "$YELLOW" "$RESET"
printf '    %s\n' "proveo init"
printf '    %s\n' "proveo run cecli-node"
printf '    %s\n' "proveo run opencode"
printf '    %s\n' "proveo run aider-node"
printf '    %s\n' "proveo run claudecode -- --debug --mcp-debug"
printf '    %s\n' "proveo run claudecode --egress-mode inspected-firewall --local-model gemma4"
printf '\n'

printf '  %s%sNotes%s\n' "$BOLD" "$YELLOW" "$RESET"
printf '    %s\n' "Docker must be installed on the host machine."
printf '    %s\n' "AI coding harnesses support pnpm monorepo scope selection inside git repos."
printf '    %s\n' "Egress modes and --local-model are orchestrated by the harness runner"
printf '    %s\n' "(proveo repo: defs/claudecode/run.sh); standalone runs use open."
printf '\n'
