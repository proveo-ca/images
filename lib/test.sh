#!/usr/bin/env bash
# Maintainer tester for proveo CLI

test_target() {
  local target="$1"
  local dir
  dir="$(target_dir "$target")"

  local test_script=""
  test_script="$(find_script_in_dir "$dir" test.sh test.bash 2>/dev/null || true)"

  if [[ -n "$test_script" ]]; then
    print_info "Running tests for $target via $(basename "$test_script")..."
    (
      cd "$dir"
      "$test_script"
    )
    print_success "Tests passed for $target"
    return 0
  fi

  case "$target" in
    claudecode|claudecode-solo)
      local claude_tests="$REPO_ROOT/defs/claudecode/tests/run_tests.sh"
      if [[ -f "$claude_tests" ]]; then
        print_info "Running tests for $target via defs/claudecode/tests/run_tests.sh..."
        "$claude_tests"
        print_success "Tests passed for $target"
        return 0
      fi
      ;;
  esac

  print_info "No test script found for $target. Skipping."
  return 0
}
