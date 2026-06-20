#!/usr/bin/env bash
# tests/test_security.sh - Security hardening verification

assert_output_contains \
  "runs as user opencode" \
  "$IMAGE" \
  "whoami" \
  "opencode"

# The image renames node:22-slim's built-in uid/gid 1000 account to "opencode"
# (see defs/opencode/Dockerfile ARG USER_ID) so host-mounted files stay
# writable. Keep this in sync with that build arg; override via EXPECTED_UID.
EXPECTED_UID="${EXPECTED_UID:-1000}"

assert_output_contains \
  "UID is $EXPECTED_UID" \
  "$IMAGE" \
  "id -u" \
  "$EXPECTED_UID"

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
