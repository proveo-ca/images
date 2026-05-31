#!/usr/bin/env bash
# tests/test_build.sh - Image build verification

# --- Build solo image ---
TESTS_RUN=$((TESTS_RUN + 1))
printf "Building solo image... "
if (cd "$PROJECT_ROOT/solo" && docker build -t "$STANDALONE_IMAGE" -f Dockerfile . 2>&1); then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} [%d] solo image builds successfully\n" "$TESTS_RUN"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("solo image builds successfully")
  printf "${RED}FAIL${NC} [%d] solo image builds successfully\n" "$TESTS_RUN"
  echo "FATAL: Cannot continue without solo image."
  print_summary
  exit 1
fi

# --- Verify Docker labels ---
assert_inspect \
  "[solo] has security.non-root=true label" \
  "$STANDALONE_IMAGE" \
  '{{index .Config.Labels "security.non-root"}}' \
  "true"

assert_inspect \
  "[solo] has security.hardened=true label" \
  "$STANDALONE_IMAGE" \
  '{{index .Config.Labels "security.hardened"}}' \
  "true"

if $MCP_IMAGE_AVAILABLE; then
  assert_inspect \
    "[mcp] has security.non-root=true label" \
    "$MCP_IMAGE" \
    '{{index .Config.Labels "security.non-root"}}' \
    "true"

  assert_inspect \
    "[mcp] has security.hardened=true label" \
    "$MCP_IMAGE" \
    '{{index .Config.Labels "security.hardened"}}' \
    "true"
fi
