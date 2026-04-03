#!/usr/bin/env bash
# tests/test_security.sh - Security hardening verification

assert_output_contains \
  "runs as user opencode" \
  "$IMAGE" \
  "whoami" \
  "opencode"

assert_output_contains \
  "UID is 1001" \
  "$IMAGE" \
  "id -u" \
  "1001"

assert_failure \
  "no setuid binaries" \
  "$IMAGE" \
  "find / -xdev -perm -4000 -type f 2>/dev/null | grep -q ."

assert_failure \
  "no setgid binaries" \
  "$IMAGE" \
  "find / -xdev -perm -2000 -type f 2>/dev/null | grep -q ."

assert_failure "nc not available" "$IMAGE" "which nc"
assert_failure "netcat not available" "$IMAGE" "which netcat"
assert_failure "netstat not available" "$IMAGE" "which netstat"
assert_failure "ss not available" "$IMAGE" "which ss"

assert_failure \
  "cannot write to /usr/bin" \
  "$IMAGE" \
  "touch /usr/bin/testfile 2>/dev/null"

assert_failure \
  "cannot write to /etc" \
  "$IMAGE" \
  "touch /etc/testfile 2>/dev/null"

assert_output_contains \
  "auto-update is disabled" \
  "$IMAGE" \
  'echo $OPENCODE_AUTO_UPDATE' \
  "false"
