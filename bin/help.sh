#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
proveo - container helper

Available containers:
  aider-node         Coding harness for Aider with Node.js, pnpm, and Playwright
  claude-standalone  Coding harness for Claude Code without extra MCP servers
  claude-chonky      Coding harness for Claude Code with Chonky MCP integrations
  charles-proxy      Utility container for running Charles Proxy headlessly

Core commands:
  proveo help
      Show this help text

  proveo list
      List supported container targets

  proveo build <target> [--no-cache]
      Build a target container image

  proveo test <target>
      Run tests or smoke tests for a target

  proveo run <target> [-- <args...>]
      Run a container target

  proveo debug <target> [-- <args...>]
      Open a debug shell or debug mode for a target

  proveo deploy <target> [--tag <tag>]
      Tag and push a target image

  proveo uninstall
      Remove proveo's bin directory from your shell PATH after confirmation

Notes:
  - AI coding harness targets support pnpm monorepo scope selection.
  - Use 'proveo list' for exact target names.
  - Keep this file updated when container targets change.
EOF
