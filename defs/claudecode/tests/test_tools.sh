#!/usr/bin/env bash
# tests/test_tools.sh - Verify all expected tools are installed

TOOLS=(
  "claude:claude --help"
  "node:node --version"
  "npm:npm --version"
  "git:git --version"
  "gh:gh --version"
  "python3:python3 --version"
  "pip3:pip3 --version"
  "curl:curl --version"
  "wget:wget --version"
  "dumb-init:dumb-init --version"
  "tsc:tsc --version"
  "ts-node:ts-node --version"
  "prettier:prettier --version"
  "eslint:eslint --version"
  "solhint:solhint --version"
  "semgrep:semgrep --version"
  "solc-select:solc-select versions"
  "solc:solc --version"
  "forge:forge --version"
  "cast:cast --version"
  "anvil:anvil --version"
)

for image in $(images_to_test); do
  tag=$(image_tag "$image")
  for tool_entry in "${TOOLS[@]}"; do
    IFS=':' read -r name cmd <<< "$tool_entry"
    assert_success "[$tag] $name is installed" "$image" "$cmd"
  done
done

# MCP-specific: no server is baked in by default; users mount or add their own.
if $MCP_IMAGE_AVAILABLE; then
  assert_success \
    "[mcp] MCP server directory exists" \
    "$MCP_IMAGE" \
    "test -d /workspace/mcp-servers"
fi
