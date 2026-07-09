#!/usr/bin/env bash
# tests/test_tools.sh - Required CLI/runtime tools are installed

assert_success \
  "cursor cli (agent) is installed and reports a version" \
  "$IMAGE" \
  "agent --version"

assert_success \
  "legacy cursor-agent alias resolves" \
  "$IMAGE" \
  "command -v cursor-agent"

assert_output_matches \
  "agent binary lives under the root-owned dist prefix" \
  "$IMAGE" \
  "readlink -f /usr/local/bin/agent" \
  "^/opt/cursor-dist/"

assert_success "git is installed" "$IMAGE" "git --version"
assert_success "gh is installed" "$IMAGE" "gh --version"
assert_success "node is installed" "$IMAGE" "node --version"
assert_success "pnpm is installed" "$IMAGE" "pnpm -v"
assert_success "python3 is installed" "$IMAGE" "python3 --version"
assert_success "docker client is installed (DinD sidecar)" "$IMAGE" "docker --version"
assert_success "playwright is installed" "$IMAGE" "playwright --version"
assert_success "playwright chromium browsers are baked" "$IMAGE" \
  'test -n "$PLAYWRIGHT_BROWSERS_PATH" && test -d "$PLAYWRIGHT_BROWSERS_PATH" && ls "$PLAYWRIGHT_BROWSERS_PATH" | grep -q chromium'
assert_success "playwright OS deps include libglib" "$IMAGE" \
  'ldconfig -p | grep -q "libglib-2.0.so.0"'
assert_success "shared verification lib is baked" "$IMAGE" \
  'command -v proveo-entrypoint >/dev/null || test -f /opt/proveo/lib/detect-verify.sh'
