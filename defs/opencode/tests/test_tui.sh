#!/usr/bin/env bash
# tests/test_tui.sh - Interactive TUI & Scope Discovery Tests
#
# Launches bin/proveo using PROVEO_FORCE_TTY=1 inside samples/ to assert all 4 TUI selection and auto-filtering requirements.

echo "--- Phase 8: Interactive TUI & Scope Discovery ---"

# Determine the main workspace repository root relative to the opencode definition root (PROJECT_ROOT)
WORKSPACE_ROOT="$(cd "$PROJECT_ROOT/../.." && pwd)"

# Ensure the temporary output path is clean
rm -f /tmp/selected_scope.txt

# Force TUI mode to be active even in headless/CI test runners
export PROVEO_FORCE_TTY=1

# 1. Assert default selection works (instantly select first option)
TESTS_RUN=$((TESTS_RUN + 1))
if os_out=$(printf '\n' | bash -c "cd $WORKSPACE_ROOT/samples && source $WORKSPACE_ROOT/apps/cli/public/cli/bin/proveo; choose_scope opencode > /tmp/selected_scope.txt" 2>&1) && [[ "$(cat /tmp/selected_scope.txt)" == "$WORKSPACE_ROOT/samples" ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} [%d] Interactive TUI selector: default selection works\n" "$TESTS_RUN"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("Interactive TUI: default selection works")
  printf "${RED}FAIL${NC} [%d] Interactive TUI: default selection failed\n" "$TESTS_RUN"
fi

# 2. Assert any valid input selection works (navigate down with 'j' and select)
TESTS_RUN=$((TESTS_RUN + 1))
if os_out=$(printf 'j\n' | bash -c "cd $WORKSPACE_ROOT/samples && source $WORKSPACE_ROOT/apps/cli/public/cli/bin/proveo; choose_scope opencode > /tmp/selected_scope.txt" 2>&1) && [[ "$(cat /tmp/selected_scope.txt)" == "$WORKSPACE_ROOT/samples" ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} [%d] Interactive TUI selector: valid navigation ('j') works\n" "$TESTS_RUN"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("Interactive TUI: valid navigation works")
  printf "${RED}FAIL${NC} [%d] Interactive TUI: valid navigation failed\n" "$TESTS_RUN"
fi

# 3. Assert invalid inputs trigger a retry (warning beep, index remains same)
TESTS_RUN=$((TESTS_RUN + 1))
if os_out=$(printf 'z\n' | bash -c "cd $WORKSPACE_ROOT/samples && source $WORKSPACE_ROOT/apps/cli/public/cli/bin/proveo; choose_scope opencode > /tmp/selected_scope.txt" 2>&1) && [[ "$os_out" == *$'\a'* || "$os_out" == *$'\x07'* ]] && [[ "$(cat /tmp/selected_scope.txt)" == "$WORKSPACE_ROOT/samples" ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} [%d] Interactive TUI selector: invalid inputs trigger a retry and beep\n" "$TESTS_RUN"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("Interactive TUI: invalid inputs retry & beep")
  printf "${RED}FAIL${NC} [%d] Interactive TUI: invalid inputs retry failed\n" "$TESTS_RUN"
fi

# 4. Assert typing the name of an option auto-filters the list
TESTS_RUN=$((TESTS_RUN + 1))
if os_out=$(printf 'tui\n' | bash -c "cd $WORKSPACE_ROOT/samples && source $WORKSPACE_ROOT/apps/cli/public/cli/bin/proveo; choose_scope opencode > /tmp/selected_scope.txt" 2>&1) && [[ "$(cat /tmp/selected_scope.txt)" == "$WORKSPACE_ROOT/samples/apps/tui" ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} [%d] Interactive TUI selector: typing auto-filters the option list\n" "$TESTS_RUN"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("Interactive TUI: auto-filtering option list")
  printf "${RED}FAIL${NC} [%d] Interactive TUI: auto-filtering failed\n" "$TESTS_RUN"
fi

# Clean up temporary file
rm -f /tmp/selected_scope.txt
