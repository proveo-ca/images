#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROVEO_BIN="$CLI_ROOT/bin/proveo"
INIT_SCRIPT="$CLI_ROOT/bin/init.sh"
INSTALL_SCRIPT="$CLI_ROOT/install.sh"
UNINSTALL_SCRIPT="$CLI_ROOT/uninstall.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILURES=()
LAST_OUTPUT=""
TEMP_ROOT=""

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
NC=$'\033[0m'

record_pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf '%sPASS%s [%d] %s\n' "$GREEN" "$NC" "$TESTS_RUN" "$1"
}

record_fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("$1")
  printf '%sFAIL%s [%d] %s\n' "$RED" "$NC" "$TESTS_RUN" "$1"
  if [[ -n "$LAST_OUTPUT" ]]; then
    printf '     Output: %.500s\n' "$LAST_OUTPUT"
  fi
}

run_test() {
  local desc="$1"
  shift
  TESTS_RUN=$((TESTS_RUN + 1))
  if LAST_OUTPUT="$($@ 2>&1)"; then
    record_pass "$desc"
  else
    record_fail "$desc"
  fi
}

assert_success() {
  local desc="$1"
  shift
  run_test "$desc" "$@"
}

assert_failure() {
  local desc="$1"
  shift
  TESTS_RUN=$((TESTS_RUN + 1))
  if LAST_OUTPUT="$($@ 2>&1)"; then
    record_fail "$desc"
  else
    record_pass "$desc"
  fi
}

assert_output_contains() {
  local desc="$1"
  local expected="$2"
  shift 2
  TESTS_RUN=$((TESTS_RUN + 1))
  if LAST_OUTPUT="$($@ 2>&1)" && [[ "$LAST_OUTPUT" == *"$expected"* ]]; then
    record_pass "$desc"
  else
    record_fail "$desc"
    printf '     Expected to contain: %s\n' "$expected"
  fi
}

assert_file_exists() {
  local desc="$1"
  local file="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  LAST_OUTPUT=""
  if [[ -f "$file" ]]; then
    record_pass "$desc"
  else
    LAST_OUTPUT="Missing file: $file"
    record_fail "$desc"
  fi
}

assert_file_executable() {
  local desc="$1"
  local file="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  LAST_OUTPUT=""
  if [[ -x "$file" ]]; then
    record_pass "$desc"
  else
    LAST_OUTPUT="File is not executable: $file"
    record_fail "$desc"
  fi
}

assert_file_contains() {
  local desc="$1"
  local file="$2"
  local expected="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  LAST_OUTPUT=""
  if [[ -f "$file" ]] && grep -Fq -- "$expected" "$file"; then
    record_pass "$desc"
  else
    LAST_OUTPUT="Expected $file to contain: $expected"
    record_fail "$desc"
  fi
}

assert_no_path() {
  local desc="$1"
  local path="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  LAST_OUTPUT=""
  if [[ ! -e "$path" ]]; then
    record_pass "$desc"
  else
    LAST_OUTPUT="Path still exists: $path"
    record_fail "$desc"
  fi
}

assert_no_match_in_file() {
  local desc="$1"
  local file="$2"
  local pattern="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  LAST_OUTPUT=""
  if [[ -f "$file" ]] && grep -Eq -- "$pattern" "$file"; then
    LAST_OUTPUT="Found forbidden Bash 4+ pattern '$pattern' in $file"
    record_fail "$desc"
  else
    record_pass "$desc"
  fi
}

make_fake_docker() {
  local bin_dir="$1"
  local log_file="$2"

  mkdir -p "$bin_dir"
  cat > "$bin_dir/docker" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >> "$log_file"
printf '\n' >> "$log_file"

case "\${1:-}" in
  image)
    if [[ "\${2:-}" == "inspect" ]]; then
      exit 0
    fi
    ;;
  pull)
    exit 0
    ;;
  run)
    exit 0
    ;;
esac

exit 0
EOF
  chmod +x "$bin_dir/docker"
}

make_fake_curl() {
  local bin_dir="$1"

  mkdir -p "$bin_dir"
  cat > "$bin_dir/curl" <<'EOF'
#!/usr/bin/env bash
src=""
dest=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      dest="$2"
      shift 2
      ;;
    -* )
      shift
      ;;
    *)
      src="$1"
      shift
      ;;
  esac
done

if [[ -z "$src" || -z "$dest" ]]; then
  exit 1
fi

src="${src#file://}"
cp "$src" "$dest"
EOF
  chmod +x "$bin_dir/curl"
}

run_cli_in_temp_dir() {
  local temp_dir="$1"
  shift
  (
    cd "$temp_dir"
    "$PROVEO_BIN" "$@"
  )
}

unset_provider_keys() {
  unset ANTHROPIC_API_KEY
  unset OPENAI_API_KEY
  unset OPENROUTER_API_KEY
  unset XAI_API_KEY
  unset GEMINI_API_KEY
  unset GOOGLE_API_KEY
  unset DEEPSEEK_API_KEY
  unset GROQ_API_KEY
  unset MISTRAL_API_KEY
  unset TOGETHER_API_KEY
  unset COHERE_API_KEY
  unset PERPLEXITY_API_KEY
  unset HUGGINGFACE_API_KEY
  unset HF_TOKEN
}

run_cli_with_git_identity() {
  local temp_dir="$1"
  shift
  (
    cd "$temp_dir"
    GIT_AUTHOR_NAME="CLITest" GIT_AUTHOR_EMAIL="cli@test.dev" "$PROVEO_BIN" "$@"
  )
}

run_init_with_openai_key() {
  local temp_dir="$1"
  (
    unset_provider_keys
    export OPENAI_API_KEY=test-openai
    cd "$temp_dir"
    "$PROVEO_BIN" init
  )
}

run_init_with_changed_openai_key() {
  local temp_dir="$1"
  (
    unset_provider_keys
    export OPENAI_API_KEY=changed
    cd "$temp_dir"
    "$PROVEO_BIN" init
  )
}

run_init_without_provider_keys() {
  local temp_dir="$1"
  (
    unset_provider_keys
    cd "$temp_dir"
    "$PROVEO_BIN" init
  )
}

assert_run_target() {
  local target="$1"
  local expected_image="$2"
  local temp_dir="$3"
  local docker_log="$4"
  shift 4
  local -a expected_parts=("$@")
  local expected_part

  : > "$docker_log"
  assert_success "proveo run $target exits successfully with stubbed Docker" run_cli_in_temp_dir "$temp_dir" run "$target"
  assert_file_contains "proveo run $target uses $expected_image" "$docker_log" "$expected_image"
  for expected_part in "${expected_parts[@]}"; do
    assert_file_contains "proveo run $target includes $expected_part" "$docker_log" "$expected_part"
  done
}

assert_run_target_forwards_args() {
  local target="$1"
  local temp_dir="$2"
  local docker_log="$3"

  : > "$docker_log"
  assert_success "proveo run $target forwards args with stubbed Docker" run_cli_in_temp_dir "$temp_dir" run "$target" -- --proveo-test-arg value
  assert_file_contains "proveo run $target forwards flag" "$docker_log" "--proveo-test-arg"
  assert_file_contains "proveo run $target forwards value" "$docker_log" "value"
}

print_summary() {
  echo ""
  echo "========================================="
  printf '  Tests run: %d\n' "$TESTS_RUN"
  printf '  %sPassed:    %d%s\n' "$GREEN" "$TESTS_PASSED" "$NC"
  printf '  %sFailed:    %d%s\n' "$RED" "$TESTS_FAILED" "$NC"
  echo "========================================="

  if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    local failure
    for failure in "${FAILURES[@]}"; do
      echo "  - $failure"
    done
    return 1
  fi

  echo ""
  echo "All distributable CLI tests passed."
}

cleanup() {
  if [[ -n "$TEMP_ROOT" ]]; then
    rm -rf "$TEMP_ROOT"
  fi
}

main() {
  TEMP_ROOT="$(mktemp -d)"
  trap cleanup EXIT

  local fake_bin="$TEMP_ROOT/bin"
  local docker_log="$TEMP_ROOT/docker.log"
  local run_dir="$TEMP_ROOT/workspace"
  mkdir -p "$run_dir"

  make_fake_docker "$fake_bin" "$docker_log"

  export PATH="$fake_bin:$PATH"
  export NO_COLOR=1

  echo "========================================="
  echo "  proveo distributable CLI test suite"
  echo "========================================="
  echo ""

  assert_success "proveo script has valid Bash syntax" bash -n "$PROVEO_BIN"
  assert_success "help script has valid Bash syntax" bash -n "$CLI_ROOT/bin/help.sh"
  assert_success "init script has valid Bash syntax" bash -n "$INIT_SCRIPT"
  assert_success "install script has valid Bash syntax" bash -n "$INSTALL_SCRIPT"
  assert_success "uninstall script has valid Bash syntax" bash -n "$UNINSTALL_SCRIPT"
  assert_success "ui script has valid Bash syntax" bash -n "$CLI_ROOT/lib/ui.sh"
  assert_success "workspace script has valid Bash syntax" bash -n "$CLI_ROOT/lib/workspace.sh"
  assert_success "runners script has valid Bash syntax" bash -n "$CLI_ROOT/lib/runners.sh"

  assert_no_match_in_file "proveo script has no Bash 4+ case modification syntax" "$PROVEO_BIN" '\$\{[a-zA-Z0-9_]+[,^]+'
  assert_no_match_in_file "proveo script has no Bash 4+ associative arrays" "$PROVEO_BIN" 'declare -A'
  assert_no_match_in_file "help script has no Bash 4+ case modification syntax" "$CLI_ROOT/bin/help.sh" '\$\{[a-zA-Z0-9_]+[,^]+'
  assert_no_match_in_file "init script has no Bash 4+ case modification syntax" "$INIT_SCRIPT" '\$\{[a-zA-Z0-9_]+[,^]+'
  assert_no_match_in_file "install script has no Bash 4+ case modification syntax" "$INSTALL_SCRIPT" '\$\{[a-zA-Z0-9_]+[,^]+'
  assert_no_match_in_file "uninstall script has no Bash 4+ case modification syntax" "$UNINSTALL_SCRIPT" '\$\{[a-zA-Z0-9_]+[,^]+'
  assert_no_match_in_file "ui script has no Bash 4+ case modification syntax" "$CLI_ROOT/lib/ui.sh" '\$\{[a-zA-Z0-9_]+[,^]+'
  assert_no_match_in_file "ui script has no Bash 4+ associative arrays" "$CLI_ROOT/lib/ui.sh" 'declare -A'
  assert_no_match_in_file "workspace script has no Bash 4+ case modification syntax" "$CLI_ROOT/lib/workspace.sh" '\$\{[a-zA-Z0-9_]+[,^]+'
  assert_no_match_in_file "workspace script has no Bash 4+ associative arrays" "$CLI_ROOT/lib/workspace.sh" 'declare -A'
  assert_no_match_in_file "runners script has no Bash 4+ case modification syntax" "$CLI_ROOT/lib/runners.sh" '\$\{[a-zA-Z0-9_]+[,^]+'
  assert_no_match_in_file "runners script has no Bash 4+ associative arrays" "$CLI_ROOT/lib/runners.sh" 'declare -A'

  assert_output_contains "proveo help prints usage" "proveo run <target>" "$PROVEO_BIN" help
  assert_output_contains "proveo help prints init" "proveo init" "$PROVEO_BIN" help
  assert_output_contains "proveo --help prints usage" "proveo run <target>" "$PROVEO_BIN" --help
  assert_output_contains "proveo with no args prints usage" "proveo run <target>" "$PROVEO_BIN"
  assert_output_contains "proveo list includes cecli" "- cecli" "$PROVEO_BIN" list
  assert_output_contains "proveo list includes cecli-node" "- cecli-node" "$PROVEO_BIN" list
  assert_output_contains "proveo version prints version" "proveo version 0.0.1" "$PROVEO_BIN" version
  assert_output_contains "proveo -v prints version" "proveo version 0.0.1" "$PROVEO_BIN" -v
  assert_output_contains "proveo --version prints version" "proveo version 0.0.1" "$PROVEO_BIN" --version
  assert_failure "proveo rejects unknown command" "$PROVEO_BIN" nope
  assert_failure "proveo rejects unknown target" "$PROVEO_BIN" run missing-target
  assert_failure "proveo list rejects extra args" "$PROVEO_BIN" list extra
  assert_failure "proveo help rejects extra args" "$PROVEO_BIN" help extra
  assert_failure "proveo init rejects extra args" "$PROVEO_BIN" init extra
  assert_failure "proveo version rejects extra args" "$PROVEO_BIN" version extra

  local init_dir="$TEMP_ROOT/init-workspace"
  mkdir -p "$init_dir"
  assert_success "proveo init creates .env from host API keys" run_init_with_openai_key "$init_dir"
  assert_file_contains "proveo init writes provider key" "$init_dir/.env" "OPENAI_API_KEY="
  assert_success "proveo init leaves existing .env unchanged" run_init_with_changed_openai_key "$init_dir"
  assert_file_contains "proveo init keeps original provider key" "$init_dir/.env" "test-openai"

  local empty_init_dir="$TEMP_ROOT/empty-init-workspace"
  mkdir -p "$empty_init_dir"
  assert_failure "proveo init fails without provider keys" run_init_without_provider_keys "$empty_init_dir"

  assert_run_target cecli "proveo/cecli:latest" "$run_dir" "$docker_log" \
    "--user $(id -u):$(id -g)" \
    "--cap-drop=ALL" \
    "--security-opt=no-new-privileges:true" \
    "--pids-limit=512" \
    "CECLI_HOME=/app/.cecli" \
    "CECLI_INSTALL_NODE_DEPS=0" \
    "$run_dir:/app" \
    "$run_dir/reports:/app/output:rw" \
    "-w" \
    "/app"
  assert_run_target_forwards_args cecli "$run_dir" "$docker_log"

  assert_run_target cecli-node "proveo/cecli-node:latest" "$run_dir" "$docker_log" \
    "--user $(id -u):$(id -g)" \
    "--cap-drop=ALL" \
    "--security-opt=no-new-privileges:true" \
    "--pids-limit=512" \
    "CECLI_HOME=/app/.cecli" \
    "CECLI_INSTALL_NODE_DEPS=0" \
    "$run_dir:/app" \
    "$run_dir/reports:/app/output:rw" \
    "-w" \
    "/app"
  assert_run_target_forwards_args cecli-node "$run_dir" "$docker_log"

  # Wrappers forward the developer's git identity (env wins over host config)
  # so agent commits inside containers are attributed to them.
  : > "$docker_log"
  assert_success "proveo run cecli forwards git identity with stubbed Docker" run_cli_with_git_identity "$run_dir" run cecli
  assert_file_contains "proveo run cecli forwards GIT_AUTHOR_NAME" "$docker_log" "GIT_AUTHOR_NAME=CLITest"
  assert_file_contains "proveo run cecli forwards GIT_COMMITTER_NAME" "$docker_log" "GIT_COMMITTER_NAME=CLITest"
  assert_file_contains "proveo run cecli forwards GIT_AUTHOR_EMAIL" "$docker_log" "GIT_AUTHOR_EMAIL=cli@test.dev"
  : > "$docker_log"
  assert_success "proveo run opencode forwards git identity with stubbed Docker" run_cli_with_git_identity "$run_dir" run opencode
  assert_file_contains "proveo run opencode forwards GIT_AUTHOR_NAME" "$docker_log" "GIT_AUTHOR_NAME=CLITest"
  : > "$docker_log"
  assert_success "proveo run claudecode-solo forwards git identity with stubbed Docker" run_cli_with_git_identity "$run_dir" run claudecode-solo
  assert_file_contains "proveo run claudecode-solo forwards GIT_AUTHOR_NAME" "$docker_log" "GIT_AUTHOR_NAME=CLITest"

  # mitmproxy is an egress sidecar, not a runnable target — `proveo run` must reject it.
  assert_failure "proveo run rejects sidecar target mitmproxy" "$PROVEO_BIN" run mitmproxy

  assert_run_target claudecode "proveo/claudecode" "$run_dir" "$docker_log" \
    "--user $(id -u):$(id -g)" \
    "--cap-drop=ALL" \
    "--security-opt=no-new-privileges:true" \
    "--pids-limit=512" \
    "$run_dir:/workspace/input:ro" \
    "$run_dir/reports:/workspace/output:rw"
  assert_run_target_forwards_args claudecode "$run_dir" "$docker_log"

  assert_run_target claudecode-solo "proveo/claudecode-solo" "$run_dir" "$docker_log" \
    "--user $(id -u):$(id -g)" \
    "--cap-drop=ALL" \
    "--security-opt=no-new-privileges:true" \
    "--pids-limit=512" \
    "$run_dir:/workspace/input:ro" \
    "$run_dir/reports:/workspace/output:rw"
  assert_run_target_forwards_args claudecode-solo "$run_dir" "$docker_log"

  assert_run_target opencode "proveo/opencode" "$run_dir" "$docker_log" \
    "--user $(id -u):$(id -g)" \
    "--cap-drop=ALL" \
    "--security-opt=no-new-privileges:true" \
    "--pids-limit=512" \
    "$run_dir:/app" \
    "-w" \
    "/app"
  assert_run_target_forwards_args opencode "$run_dir" "$docker_log"

  # Egress enforcement modes are not shipped in the installed CLI; requesting one
  # must FAIL CLOSED (exit non-zero) rather than silently run with open egress.
  : > "$docker_log"
  assert_failure "proveo run claudecode --egress-mode proxy fails closed" \
    run_cli_in_temp_dir "$run_dir" run claudecode --egress-mode proxy
  # The rejection exits non-zero, so capture its output directly (assert_output_contains
  # requires success) and confirm it explains why enforcement is unavailable.
  TESTS_RUN=$((TESTS_RUN + 1))
  LAST_OUTPUT="$(run_cli_in_temp_dir "$run_dir" run claudecode --egress-mode firewall 2>&1 || true)"
  if [[ "$LAST_OUTPUT" == *"not available in the installed proveo CLI"* ]]; then
    record_pass "egress-mode rejection is explained"
  else
    record_fail "egress-mode rejection is explained"
  fi
  # open mode is accepted and must not leak the flag into the container args.
  : > "$docker_log"
  assert_success "proveo run claudecode --egress-mode open is accepted" \
    run_cli_in_temp_dir "$run_dir" run claudecode --egress-mode open
  assert_file_contains "claudecode still launches its image under open egress" "$docker_log" "proveo/claudecode"

  local install_home="$TEMP_ROOT/home"
  local install_root="$TEMP_ROOT/install-root"
  local install_fake_bin="$TEMP_ROOT/install-bin"
  mkdir -p "$install_home" "$install_fake_bin"
  make_fake_curl "$install_fake_bin"

  assert_output_contains \
    "install.sh installs and prints version" \
    "proveo v0.0.1 installed to:" \
    env \
      HOME="$install_home" \
      SHELL=/bin/bash \
      PATH="$install_fake_bin:$PATH" \
      PROVEO_INSTALL_ROOT="$install_root" \
      PROVEO_ASSET_BASE_URL="file://$CLI_ROOT" \
      PROVEO_CLI_BASE_URL="file://$CLI_ROOT" \
      "$INSTALL_SCRIPT"
  assert_file_exists "install writes proveo binary" "$install_root/bin/proveo"
  assert_file_exists "install writes help script" "$install_root/bin/help.sh"
  assert_file_exists "install writes init script" "$install_root/bin/init.sh"
  assert_file_exists "install writes uninstall script" "$install_root/uninstall.sh"
  assert_file_exists "install writes ui helper" "$install_root/lib/ui.sh"
  assert_file_exists "install writes workspace helper" "$install_root/lib/workspace.sh"
  assert_file_exists "install writes runners helper" "$install_root/lib/runners.sh"
  assert_file_executable "installed proveo is executable" "$install_root/bin/proveo"
  assert_file_executable "installed init script is executable" "$install_root/bin/init.sh"
  # install.sh appends the PATH marker to the shell-appropriate rc file, and for
  # bash that differs by OS: macOS uses ~/.bash_profile, other systems ~/.bashrc
  # (mirrors shell_config_file in install.sh). Check the right one per platform.
  local install_rc="$install_home/.bashrc"
  [[ "$(uname -s)" == "Darwin" ]] && install_rc="$install_home/.bash_profile"
  assert_file_contains "install writes PATH marker" "$install_rc" "# Added by proveo install.sh"
  assert_output_contains "installed proveo can list targets" "- cecli-node" "$install_root/bin/proveo" list
  assert_failure "installed proveo uninstall rejects extra args" "$install_root/bin/proveo" uninstall extra

  assert_success \
    "installed proveo uninstall removes temp install root" \
    env \
      HOME="$install_home" \
      PROVEO_UNINSTALL_ASSUME_YES=1 \
      "$install_root/bin/proveo" uninstall
  assert_no_path "uninstall removes install root" "$install_root"
  assert_success "canonical uninstall script is callable with safe temp root" env HOME="$install_home" PROVEO_INSTALL_ROOT="$TEMP_ROOT/missing-root" PROVEO_UNINSTALL_ASSUME_YES=1 "$UNINSTALL_SCRIPT"

  print_summary
}

main "$@"
