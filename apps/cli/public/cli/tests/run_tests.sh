#!/usr/bin/env bash
# bash consumer surface is a thin list/help/menu + exec proveo.
# Full run orchestration is the Go binary (cmd/proveo).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASH_PROVEO="$CLI_ROOT/bin/proveo"
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
 printf ' Output: %.500s\n' "$LAST_OUTPUT"
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
 printf ' Expected to contain: %s\n' "$expected"
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

make_fake_proveo() {
 local bin_dir="$1"
 local log_file="$2"
 mkdir -p "$bin_dir"
 cat > "$bin_dir/proveo" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >> "$log_file"
printf '\n' >> "$log_file"
exit 0
EOF
 chmod +x "$bin_dir/proveo"
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
 -o) dest="$2"; shift 2 ;;
 -*) shift ;;
 *) src="$1"; shift ;;
 esac
done
[[ -n "$src" && -n "$dest" ]] || exit 1
src="${src#file://}"
cp "$src" "$dest"
EOF
 chmod +x "$bin_dir/curl"
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
 local proveo_log="$TEMP_ROOT/proveo.log"
 mkdir -p "$fake_bin"
 make_fake_proveo "$fake_bin" "$proveo_log"

 export NO_COLOR=1
 # Fake Go proveo is only used when bash run delegates (PROVEO_BIN=).
 # Do NOT put it first on PATH for list/help/version — those are pure bash.

 echo "========================================="
 echo " proveo distributable CLI test suite"
 echo ""
 echo "========================================="
 echo ""

 assert_success "proveo script has valid Bash syntax" bash -n "$BASH_PROVEO"
 assert_success "help script has valid Bash syntax" bash -n "$CLI_ROOT/bin/help.sh"
 assert_success "init script has valid Bash syntax" bash -n "$INIT_SCRIPT"
 assert_success "install script has valid Bash syntax" bash -n "$INSTALL_SCRIPT"
 assert_success "uninstall script has valid Bash syntax" bash -n "$UNINSTALL_SCRIPT"
 assert_success "ui script has valid Bash syntax" bash -n "$CLI_ROOT/lib/ui.sh"
 assert_success "runners script has valid Bash syntax" bash -n "$CLI_ROOT/lib/runners.sh"

 assert_no_match_in_file "proveo script has no Bash 4+ case modification syntax" "$BASH_PROVEO" '\$\{[a-zA-Z0-9_]+[,^]+'
 assert_no_match_in_file "runners script has no Bash 4+ case modification syntax" "$CLI_ROOT/lib/runners.sh" '\$\{[a-zA-Z0-9_]+[,^]+'
 assert_no_match_in_file "runners script has no Bash 4+ associative arrays" "$CLI_ROOT/lib/runners.sh" 'declare -A'

 assert_file_contains "runners exec the Go proveo binary" "$CLI_ROOT/lib/runners.sh" 'exec "$bin" run'

 assert_output_contains "proveo help prints usage" "proveo run" "$BASH_PROVEO" help
 assert_output_contains "proveo list includes cecli" "cecli" "$BASH_PROVEO" list
 assert_output_contains "proveo list includes cursor" "cursor" "$BASH_PROVEO" list
 assert_output_contains "proveo version prints version" "proveo version" "$BASH_PROVEO" version
 assert_failure "proveo rejects unknown command" "$BASH_PROVEO" nope

 : > "$proveo_log"
 assert_success "proveo run opencode delegates to Go proveo" \
 env PROVEO_BIN="$fake_bin/proveo" "$BASH_PROVEO" run opencode
 assert_file_contains "delegated argv includes run opencode" "$proveo_log" "run opencode"

 : > "$proveo_log"
 assert_success "proveo run cursor delegates to Go proveo" \
 env PROVEO_BIN="$fake_bin/proveo" "$BASH_PROVEO" run cursor -- --force
 assert_file_contains "delegated argv includes run cursor" "$proveo_log" "run cursor"

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
 assert_file_exists "install writes ui helper" "$install_root/lib/ui.sh"
 assert_file_exists "install writes runners helper" "$install_root/lib/runners.sh"
 assert_no_path "install no longer ships workspace.sh" "$install_root/lib/workspace.sh"
 assert_no_path "install no longer ships dind.sh" "$install_root/lib/dind.sh"
 assert_file_executable "installed proveo is executable" "$install_root/bin/proveo"

 assert_success \
 "installed proveo uninstall removes temp install root" \
 env \
 HOME="$install_home" \
 PROVEO_UNINSTALL_ASSUME_YES=1 \
 "$install_root/bin/proveo" uninstall
 assert_no_path "uninstall removes install root" "$install_root"

 echo ""
 echo "========================================="
 printf ' Tests run: %d\n' "$TESTS_RUN"
 printf ' %sPassed: %d%s\n' "$GREEN" "$TESTS_PASSED" "$NC"
 printf ' %sFailed: %d%s\n' "$RED" "$TESTS_FAILED" "$NC"
 echo "========================================="

 if [[ ${#FAILURES[@]} -gt 0 ]]; then
 echo ""
 echo "Failed tests:"
 local failure
 for failure in "${FAILURES[@]}"; do
 echo " - $failure"
 done
 return 1
 fi

 echo ""
 echo "All distributable CLI tests passed."
}

main "$@"
