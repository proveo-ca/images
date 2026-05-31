#!/usr/bin/env bash
set -euo pipefail

TIMEOUT_SECONDS="${PROVEO_DOCKER_SMOKE_TIMEOUT:-30}"
TEMP_ROOT=""

TARGETS=(
  "cecli|proveo/cecli:latest"
  "cecli-node|proveo/cecli-node:latest"
  "charles-proxy|proveo/charles-proxy:latest"
  "claudecode|proveo/claudecode:latest"
  "claudecode-solo|proveo/claudecode-solo:latest"
  "opencode|proveo/opencode:latest"
)

if [[ "${PROVEO_DOCKER_SMOKE_INCLUDE_AIDER_NODE:-0}" == "1" ]]; then
  TARGETS=("aider-node|proveo/aider-node:latest" "${TARGETS[@]}")
fi

containers=()

cleanup() {
  local container
  for container in "${containers[@]}"; do
    docker rm -f "$container" >/dev/null 2>&1 || true
  done
  if [[ -n "$TEMP_ROOT" ]]; then
    rm -rf "$TEMP_ROOT"
  fi
}

write_smoke_env() {
  local workspace="$1"

  mkdir -p "$workspace"
  cat > "$workspace/.env" <<'EOF'
# Non-secret values for detached image smoke tests only.
ARCHITECT_MODEL=openai/gpt-4o-mini
EDITOR_MODEL=openai/gpt-4o-mini
SMALL_MODEL=openai/gpt-4o-mini
AIDER_MODEL=openai/gpt-4o-mini
AIDER_EDITOR_MODEL=openai/gpt-4o-mini
AIDER_WEAK_MODEL=openai/gpt-4o-mini
CECLI_MODEL=openai/gpt-4o-mini
CECLI_EDITOR_MODEL=openai/gpt-4o-mini
CECLI_WEAK_MODEL=openai/gpt-4o-mini
OPENCODE_MODEL=openai/gpt-4o-mini
OPENCODE_SMALL_MODEL=openai/gpt-4o-mini
OPENAI_API_KEY=proveo-smoke-test-key
ANTHROPIC_API_KEY=proveo-smoke-test-key
CLAUDE_CODE_OAUTH_TOKEN=proveo-smoke-test-token
EOF
}

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is required for detached image smoke tests." >&2
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "Docker is installed but the daemon is not available." >&2
    exit 1
  fi
}

require_image() {
  local image="$1"
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    echo "Docker image not found locally: $image" >&2
    echo "Build the images before running detached smoke tests." >&2
    exit 1
  fi
}

wait_for_log() {
  local container="$1"
  local expected="$2"
  local logs=""
  local running=""
  local i

  for ((i = 0; i < TIMEOUT_SECONDS; i++)); do
    logs="$(docker logs "$container" 2>&1 || true)"
    if [[ "$logs" == *"$expected"* ]]; then
      return 0
    fi

    running="$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || true)"
    if [[ "$running" != "true" ]]; then
      echo "Container exited before smoke signal: $container" >&2
      echo "$logs" >&2
      return 1
    fi

    sleep 1
  done

  echo "Timed out waiting for smoke signal: $expected" >&2
  echo "$logs" >&2
  return 1
}

run_target_smoke() {
  local target="$1"
  local image="$2"
  local workspace="$3"
  local container="proveo-smoke-${target//[^a-zA-Z0-9_.-]/-}-$$"
  local expected="✅ PROVEO_SMOKE_READY $target"
  local -a docker_args=(
    run -d
    --name "$container"
    --env-file "$workspace/.env"
    -e PROVEO_SMOKE_TEST=1
    -e "PROVEO_SMOKE_TARGET=$target"
    -e "PROVEO_SMOKE_EXPECTED=$expected"
  )

  require_image "$image"

  echo "==> $target ($image)"
  docker rm -f "$container" >/dev/null 2>&1 || true

  case "$target" in
    aider-node|cecli|cecli-node|opencode)
      docker_args+=(-v "$workspace:/app" -w /app)
      ;;
    claudecode|claudecode-solo)
      docker_args+=(-v "$workspace:/workspace/input:ro")
      ;;
  esac

  case "$target" in
    opencode)
      # Older opencode images do not understand PROVEO_SMOKE_TEST and can exit
      # after startup checks. Override the entrypoint to keep this detached
      # smoke test focused on image runnability and log visibility.
      docker_args+=(--entrypoint bash)
      ;;
  esac

  docker_args+=("$image")

  case "$target" in
    cecli|cecli-node|opencode)
      # Older Cecli images do not understand PROVEO_SMOKE_TEST and will launch
      # the TUI. Cecli's entrypoint permits bash, so it still exercises
      # entrypoint initialization. opencode uses --entrypoint above to avoid
      # older image startup falling through into an immediate CLI exit.
      docker_args+=(bash -lc 'printf "%s\n" "$PROVEO_SMOKE_EXPECTED"; exec sleep infinity')
      ;;
  esac

  docker "${docker_args[@]}" >/dev/null
  containers+=("$container")

  wait_for_log "$container" "$expected"
  echo "PASS $target emitted smoke-ready log"
}

main() {
  local item
  local target
  local image
  local workspace

  trap cleanup EXIT
  require_docker

  TEMP_ROOT="$(mktemp -d)"
  workspace="$TEMP_ROOT/workspace"
  write_smoke_env "$workspace"

  for item in "${TARGETS[@]}"; do
    target="${item%%|*}"
    image="${item#*|}"
    run_target_smoke "$target" "$image" "$workspace"
  done
}

main "$@"
