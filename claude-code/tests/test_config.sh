#!/usr/bin/env bash
# tests/test_config.sh - Claude configuration verification

# ==================== Standalone ====================

IMAGE="$STANDALONE_IMAGE"

# Config file existence
assert_success \
  "[standalone] ~/.claude.json exists" \
  "$IMAGE" \
  "test -f /home/claude/.claude.json"

assert_output_contains \
  "[standalone] ~/.claude.json owned by claude" \
  "$IMAGE" \
  "stat -c '%U' /home/claude/.claude.json" \
  "claude"

# Key config values
assert_output_contains \
  "[standalone] dangerouslySkipPermissions=true" \
  "$IMAGE" \
  "cat /home/claude/.claude.json" \
  '"dangerouslySkipPermissions": true'

assert_output_contains \
  "[standalone] autoTrustNewProjects=true" \
  "$IMAGE" \
  "cat /home/claude/.claude.json" \
  '"autoTrustNewProjects": true'

assert_output_contains \
  "[standalone] has /workspace project" \
  "$IMAGE" \
  "cat /home/claude/.claude.json" \
  '"/workspace"'

assert_output_contains \
  '[standalone] allowedTools includes wildcard' \
  "$IMAGE" \
  "cat /home/claude/.claude.json" \
  '"*"'

assert_output_contains \
  "[standalone] hasCompletedOnboarding=true" \
  "$IMAGE" \
  "cat /home/claude/.claude.json" \
  '"hasCompletedOnboarding": true'

# mcpServers should be empty
assert_output_matches \
  "[standalone] mcpServers is empty" \
  "$IMAGE" \
  "python3 -c \"import json; c=json.load(open('/home/claude/.claude.json')); print(len(c['projects']['/workspace']['mcpServers']))\"" \
  "^0$"

# settings.local.json
assert_success \
  "[standalone] ~/.claude/settings.local.json exists" \
  "$IMAGE" \
  "test -f /home/claude/.claude/settings.local.json"

assert_success \
  "[standalone] /workspace/.claude/settings.local.json exists" \
  "$IMAGE" \
  "test -f /workspace/.claude/settings.local.json"

assert_success \
  "[standalone] settings.local.json is valid JSON" \
  "$IMAGE" \
  "python3 -c \"import json; json.load(open('/home/claude/.claude/settings.local.json'))\""

# ==================== MCP ====================

if $MCP_IMAGE_AVAILABLE; then
  IMAGE="$MCP_IMAGE"

  assert_success \
    "[mcp] ~/.claude.json exists" \
    "$IMAGE" \
    "test -f /home/claude/.claude.json"

  assert_output_contains \
    "[mcp] dangerouslySkipPermissions=true" \
    "$IMAGE" \
    "cat /home/claude/.claude.json" \
    '"dangerouslySkipPermissions": true'

  assert_output_contains \
    "[mcp] hasCompletedOnboarding=true" \
    "$IMAGE" \
    "cat /home/claude/.claude.json" \
    '"hasCompletedOnboarding": true'

  # MCP server configured
  assert_output_contains \
    "[mcp] mcpServers has chonky key" \
    "$IMAGE" \
    "cat /home/claude/.claude.json" \
    '"chonky"'

  assert_output_contains \
    "[mcp] chonky command is node" \
    "$IMAGE" \
    "cat /home/claude/.claude.json" \
    '"command": "node"'

  assert_output_contains \
    "[mcp] chonky points to correct index.js" \
    "$IMAGE" \
    "cat /home/claude/.claude.json" \
    '/workspace/mcp-servers/chonky-mcp-server/build/index.js'

  assert_output_contains \
    "[mcp] chonky is trusted" \
    "$IMAGE" \
    "cat /home/claude/.claude.json" \
    '"trusted": true'

  assert_output_contains \
    "[mcp] chonky has autoStart" \
    "$IMAGE" \
    "cat /home/claude/.claude.json" \
    '"autoStart": true'

  assert_output_contains \
    "[mcp] chonky has CHONKY_PRIMER_REPOS env" \
    "$IMAGE" \
    "cat /home/claude/.claude.json" \
    'CHONKY_PRIMER_REPOS'

  # MCP permissions in settings.local
  assert_output_contains \
    "[mcp] settings.local.json allows mcp__chonky" \
    "$IMAGE" \
    "cat /home/claude/.claude/settings.local.json" \
    'mcp__chonky'
fi
