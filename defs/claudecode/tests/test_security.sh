#!/usr/bin/env bash
# tests/test_security.sh - Security hardening verification

for image in $(images_to_test); do
  tag=$(image_tag "$image")

  # Running user
  assert_output_contains \
    "[$tag] runs as user claude" \
    "$image" \
    "whoami" \
    "claude"

  assert_output_contains \
    "[$tag] UID is 1001" \
    "$image" \
    "id -u" \
    "1001"

  # No setuid/setgid binaries
  assert_failure \
    "[$tag] no setuid binaries" \
    "$image" \
    "find / -xdev -perm -4000 -type f 2>/dev/null | grep -q ."

  assert_failure \
    "[$tag] no setgid binaries" \
    "$image" \
    "find / -xdev -perm -2000 -type f 2>/dev/null | grep -q ."

  # Network recon tools removed
  assert_failure "[$tag] nc not available" "$image" "which nc"
  assert_failure "[$tag] netcat not available" "$image" "which netcat"
  assert_failure "[$tag] netstat not available" "$image" "which netstat"
  assert_failure "[$tag] ss not available" "$image" "which ss"

  # Cannot write to system dirs
  assert_failure \
    "[$tag] cannot write to /usr/bin" \
    "$image" \
    "touch /usr/bin/testfile 2>/dev/null"

  assert_failure \
    "[$tag] cannot write to /etc" \
    "$image" \
    "touch /etc/testfile 2>/dev/null"

  # Environment variables
  assert_output_contains \
    "[$tag] NODE_ENV is production" \
    "$image" \
    'echo $NODE_ENV' \
    "production"

  assert_output_contains \
    "[$tag] RLIMIT_CORE is 0" \
    "$image" \
    'echo $RLIMIT_CORE' \
    "0"

  # Entrypoint uses dumb-init
  assert_inspect \
    "[$tag] entrypoint uses dumb-init" \
    "$image" \
    '{{json .Config.Entrypoint}}' \
    "dumb-init"

  # Node version is v20.x
  assert_output_matches \
    "[$tag] node version is v20.x" \
    "$image" \
    "node --version" \
    "^v20\."

  # Docker USER is non-root
  assert_inspect \
    "[$tag] Docker USER is non-root" \
    "$image" \
    '{{.Config.User}}' \
    "claude"
done
