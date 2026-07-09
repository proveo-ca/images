#!/usr/bin/env bash
# tests/test_tools.sh - Verify expected tools/runtimes are installed

TOOLS=(
  "opencode:opencode --version"
  "node:node --version"
  "npm:npm --version"
  "pnpm:timeout 10s pnpm --version"
  "git:git --version"
  "gh:gh --version"
  "curl:curl --version"
  "dumb-init:dumb-init --version"
  "playwright:playwright --version"
)

for tool_entry in "${TOOLS[@]}"; do
  IFS=':' read -r name cmd <<< "$tool_entry"
  assert_success "$name is installed" "$IMAGE" "$cmd"
done

# Node major version: 22
assert_output_matches \
  "node version is v22.x" \
  "$IMAGE" \
  "node --version" \
  "^v22\."

assert_success "playwright chromium browsers are baked" "$IMAGE" \
  'test -n "$PLAYWRIGHT_BROWSERS_PATH" && test -d "$PLAYWRIGHT_BROWSERS_PATH" && ls "$PLAYWRIGHT_BROWSERS_PATH" | grep -q chromium'

# opencode CLI exposes the `run` subcommand
assert_output_contains \
  "opencode CLI exposes 'run' subcommand" \
  "$IMAGE" \
  "opencode --help 2>&1" \
  "run"
