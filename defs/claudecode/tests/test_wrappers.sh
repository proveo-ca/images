#!/usr/bin/env bash
# tests/test_wrappers.sh - Wrapper contract checks that do not require Docker.

WRAPPER_FILES=(
  "$PROJECT_ROOT/mcp/run.sh"
  "$PROJECT_ROOT/solo/run.sh"
  "$PROJECT_ROOT/mcp/debug.sh"
  "$PROJECT_ROOT/solo/debug.sh"
)

for wrapper in "${WRAPPER_FILES[@]}"; do
  name="${wrapper#$PROJECT_ROOT/}"

  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -q 'INPUT_DIR}/.claude' "$wrapper" \
     && grep -q '/workspace/.claude:ro' "$wrapper" \
     && grep -q 'HOME:-}/.claude' "$wrapper" \
     && grep -q '/home/claude/.claude:ro' "$wrapper"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${GREEN}PASS${NC} [%d] [%s] mounts project/home .claude config folders\n" "$TESTS_RUN" "$name"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES+=("[$name] mounts project/home .claude config folders")
    printf "${RED}FAIL${NC} [%d] [%s] missing .claude wrapper mount contract\n" "$TESTS_RUN" "$name"
  fi
done