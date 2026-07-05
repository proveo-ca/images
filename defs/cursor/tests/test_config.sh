#!/usr/bin/env bash
# tests/test_config.sh - Entrypoint behavior: smoke mode, proxy compat, preamble

# Smoke mode: entrypoint completes setup, prints the ready marker, then parks.
TESTS_RUN=$((TESTS_RUN + 1))
SMOKE_OUTPUT=$(run_timeout 60 docker run --rm \
  -e PROVEO_SMOKE_TEST=1 \
  --entrypoint bash \
  "$IMAGE" -c "timeout 10 /entrypoint.sh; true" 2>&1 || true)
if echo "$SMOKE_OUTPUT" | grep -q "PROVEO_SMOKE_READY cursor"; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} [%d] smoke mode prints PROVEO_SMOKE_READY\n" "$TESTS_RUN"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("smoke mode prints PROVEO_SMOKE_READY")
  printf "${RED}FAIL${NC} [%d] smoke mode (output: %.300s)\n" "$TESTS_RUN" "$SMOKE_OUTPUT"
fi

# Entrypoint preamble reports the paradigm and the policy layer.
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SMOKE_OUTPUT" | grep -q "policy-gated autonomous loop"; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} [%d] preamble states the paradigm\n" "$TESTS_RUN"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("preamble states the paradigm")
  printf "${RED}FAIL${NC} [%d] preamble states the paradigm (output: %.300s)\n" "$TESTS_RUN" "$SMOKE_OUTPUT"
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SMOKE_OUTPUT" | grep -q "Deny rules (survive --force)"; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} [%d] preamble reports the deny-rule baseline\n" "$TESTS_RUN"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("preamble reports the deny-rule baseline")
  printf "${RED}FAIL${NC} [%d] preamble reports the deny-rule baseline\n" "$TESTS_RUN"
fi

TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SMOKE_OUTPUT" | grep -q "Subagents available:"; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} [%d] preamble lists seeded subagents\n" "$TESTS_RUN"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("preamble lists seeded subagents")
  printf "${RED}FAIL${NC} [%d] preamble lists seeded subagents\n" "$TESTS_RUN"
fi

# Proxy detection flips useHttp1ForAgent in the seeded config. Drive the
# entrypoint with --version (utility passthrough) so it exits immediately.
TESTS_RUN=$((TESTS_RUN + 1))
RESULT=$(run_timeout 60 docker run --rm \
  -e HTTPS_PROXY=http://squid:3128 \
  --entrypoint bash \
  "$IMAGE" -c '/entrypoint.sh --version >/dev/null 2>&1; grep -c "\"useHttp1ForAgent\": true" "$HOME/.cursor/cli-config.json"' 2>&1 || true)
if echo "$RESULT" | grep -q "^1$"; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} [%d] proxy env sets useHttp1ForAgent=true in seeded config\n" "$TESTS_RUN"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("proxy env sets useHttp1ForAgent=true in seeded config")
  printf "${RED}FAIL${NC} [%d] useHttp1ForAgent behaviour (output: %.300s)\n" "$TESTS_RUN" "$RESULT"
fi

# Without a proxy, the entrypoint never enables the HTTP/1.1 fallback. (The CLI
# itself normalizes the config on launch and writes the key as false — so
# assert on ": true", not on the key's presence.)
TESTS_RUN=$((TESTS_RUN + 1))
RESULT=$(run_timeout 60 docker run --rm \
  --entrypoint bash \
  "$IMAGE" -c '/entrypoint.sh --version >/dev/null 2>&1; grep -c "\"useHttp1ForAgent\": true" "$HOME/.cursor/cli-config.json" || true' 2>&1 || true)
if echo "$RESULT" | grep -q "^0$"; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} [%d] no proxy env leaves useHttp1ForAgent disabled\n" "$TESTS_RUN"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("no proxy env leaves useHttp1ForAgent disabled")
  printf "${RED}FAIL${NC} [%d] proxy-less config (output: %.300s)\n" "$TESTS_RUN" "$RESULT"
fi
