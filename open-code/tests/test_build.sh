#!/usr/bin/env bash
# tests/test_build.sh - Image build verification

TESTS_RUN=$((TESTS_RUN + 1))
printf "Building image %s... " "$IMAGE"
if (cd "$PROJECT_ROOT" && docker build -t "$IMAGE" -f Dockerfile . 2>&1); then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "${GREEN}PASS${NC} [%d] image builds successfully\n" "$TESTS_RUN"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES+=("image builds successfully")
  printf "${RED}FAIL${NC} [%d] image builds successfully\n" "$TESTS_RUN"
  echo "FATAL: Cannot continue without image."
  print_summary
  exit 1
fi

assert_inspect \
  "has security.non-root=true label" \
  "$IMAGE" \
  '{{index .Config.Labels "security.non-root"}}' \
  "true"

assert_inspect \
  "has security.hardened=true label" \
  "$IMAGE" \
  '{{index .Config.Labels "security.hardened"}}' \
  "true"

assert_inspect \
  "Docker USER is non-root (opencode)" \
  "$IMAGE" \
  '{{.Config.User}}' \
  "opencode"

assert_inspect \
  "entrypoint uses dumb-init" \
  "$IMAGE" \
  '{{json .Config.Entrypoint}}' \
  "dumb-init"
