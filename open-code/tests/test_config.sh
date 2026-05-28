#!/usr/bin/env bash
# tests/test_config.sh - Entrypoint configuration detection
#
# Exercise entrypoint.sh by mounting a small fixture project into /app and
# running it without args (TUI launch is short-circuited by feeding no TTY +
# `--help` style discoveries; here we just inspect the preamble output).

FIXTURE_DIR=$(mktemp -d)
trap 'rm -rf "$FIXTURE_DIR"' RETURN

cat >"$FIXTURE_DIR/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "anthropic/claude-sonnet-4-5"
}
EOF
cat >"$FIXTURE_DIR/AGENTS.md" <<'EOF'
# Test fixture agents file.
EOF
cat >"$FIXTURE_DIR/.env" <<'EOF'
OPENCODE_TEST_MARKER=loaded_from_env
EOF

# Run the entrypoint but force the inner `exec opencode` to short-circuit by
# sending an unsupported flag that exits quickly. `opencode --version` exits 0
# after printing.
TESTS_RUN=$((TESTS_RUN + 1))
RESULT=$(docker run --rm \
  -v "$FIXTURE_DIR:/app" \
  --entrypoint /entrypoint.sh \
  "$IMAGE" --version 2>&1 || true)
if echo "$RESULT" | grep -q "Found opencode.json" \
   && echo "$RESULT" | grep -q "Found AGENTS.md" \
   && echo "$RESULT" | grep -q "Loaded environment variables from .env"; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} [%d] entrypoint detects opencode.json + AGENTS.md + .env\n" "$TESTS_RUN"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("entrypoint detects opencode.json + AGENTS.md + .env")
  printf "${RED}FAIL${NC} [%d] entrypoint detects config (output: %.300s)\n" "$TESTS_RUN" "$RESULT"
fi

# Entrypoint forwards args to opencode
TESTS_RUN=$((TESTS_RUN + 1))
RESULT=$(docker run --rm "$IMAGE" --version 2>&1 || true)
if echo "$RESULT" | grep -qE "[0-9]+\.[0-9]+"; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} [%d] entrypoint forwards args to opencode (--version)\n" "$TESTS_RUN"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("entrypoint forwards args to opencode (--version)")
  printf "${RED}FAIL${NC} [%d] entrypoint forwards args (output: %.300s)\n" "$TESTS_RUN" "$RESULT"
fi
