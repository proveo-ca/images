#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
proveo - container helper

Available containers:
  aider-node         Coding harness for Aider with Node.js, pnpm, and Playwright
  claude-code        Default Claude Code container with MCP integrations
  claude-code-solo   Claude Code container without the default MCP-integrated stack
  charles-proxy      Utility container for running Charles Proxy headlessly

Core commands:
  proveo help
      Show this help text

  proveo list
      List supported container targets

  proveo run <target> [-- <args...>]
      Run a container target

  proveo uninstall
      Remove proveo's installed bin directory from your shell PATH after confirmation

Notes:
  - proveo is the consumer CLI.
  - AI coding harness targets support pnpm monorepo scope selection when run inside a git repo.
  - Docker must be installed on the host machine.
  - Keep this file updated when container targets change.
EOF
