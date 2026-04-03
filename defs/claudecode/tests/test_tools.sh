#!/usr/bin/env bash
# tests/test_tools.sh - Verify all expected tools are installed

TOOLS=(
  "claude:claude --help"
  "node:node --version"
  "npm:npm --version"
  "git:git --version"
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

# MCP-specific: verify MCP server files
if $MCP_IMAGE_AVAILABLE; then
  assert_success \
    "[mcp] MCP server build/index.js exists" \
    "$MCP_IMAGE" \
    "test -f /workspace/mcp-servers/chonky-mcp-server/build/index.js"

  assert_success \
    "[mcp] MCP server node_modules present" \
    "$MCP_IMAGE" \
    "test -d /workspace/mcp-servers/chonky-mcp-server/node_modules"
fi
