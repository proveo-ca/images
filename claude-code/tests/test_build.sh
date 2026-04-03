#!/usr/bin/env bash
# tests/test_build.sh - Image build verification

# --- Build standalone image ---
TESTS_RUN=$((TESTS_RUN + 1))
printf "Building standalone image... "
if (cd "$PROJECT_ROOT/claude-standalone" && docker build -t "$STANDALONE_IMAGE" -f Dockerfile . 2>&1); then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} [%d] Standalone image builds successfully\n" "$TESTS_RUN"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("Standalone image builds successfully")
  printf "${RED}FAIL${NC} [%d] Standalone image builds successfully\n" "$TESTS_RUN"
  echo "FATAL: Cannot continue without standalone image."
  print_summary
  exit 1
fi

# --- Build MCP image (conditional) ---
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -d "$PROJECT_ROOT/claude-with-mcp-example/mcp/chonky" ]] && \
   [[ -f "$PROJECT_ROOT/claude-with-mcp-example/mcp/chonky/package.json" ]]; then
  printf "Building MCP image... "
  if (cd "$PROJECT_ROOT/claude-with-mcp-example" && docker build -f Dockerfile.chonky -t "$MCP_IMAGE" . 2>&1); then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    MCP_IMAGE_AVAILABLE=true
    printf "${GREEN}PASS${NC} [%d] MCP image builds successfully\n" "$TESTS_RUN"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES+=("MCP image builds successfully")
    printf "${RED}FAIL${NC} [%d] MCP image builds successfully\n" "$TESTS_RUN"
  fi
else
  skip_test "MCP image builds successfully" "mcp/chonky/package.json not found"
fi

# --- Verify Docker labels ---
assert_inspect \
  "[standalone] has security.non-root=true label" \
  "$STANDALONE_IMAGE" \
  '{{index .Config.Labels "security.non-root"}}' \
  "true"

assert_inspect \
  "[standalone] has security.hardened=true label" \
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
