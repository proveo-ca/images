#!/usr/bin/env bash
# Docker target runners helper module for proveo CLI

# Forward the developer's git identity (GIT_* env wins, else host git config) as
# `-e` pairs in PROVEO_GIT_IDENTITY_ARGS; standalone mirror of defs/lib/git-identity.sh.
proveo_git_identity_env_args() {
  PROVEO_GIT_IDENTITY_ARGS=()

  local name email
  name="${GIT_AUTHOR_NAME:-${GIT_COMMITTER_NAME:-}}"
  email="${GIT_AUTHOR_EMAIL:-${GIT_COMMITTER_EMAIL:-}}"

  if command -v git >/dev/null 2>&1; then
    [[ -n "$name" ]] || name="$(git config --get user.name 2>/dev/null || true)"
    [[ -n "$email" ]] || email="$(git config --get user.email 2>/dev/null || true)"
  fi

  if [[ -n "$name" ]]; then
    PROVEO_GIT_IDENTITY_ARGS+=(-e "GIT_AUTHOR_NAME=$name" -e "GIT_COMMITTER_NAME=$name")
  fi

  if [[ -n "$email" ]]; then
    PROVEO_GIT_IDENTITY_ARGS+=(-e "GIT_AUTHOR_EMAIL=$email" -e "GIT_COMMITTER_EMAIL=$email")
  fi
}

image_name() {
  local target="$1"
  case "$target" in
    cecli)
      echo "proveo/cecli"
      ;;
    cecli-node)
      echo "proveo/cecli-node"
      ;;
    opencode)
      echo "proveo/opencode"
      ;;
    claudecode)
      echo "proveo/claudecode"
      ;;
    claudecode-solo)
      echo "proveo/claudecode-solo"
      ;;
    claudecode-sol)
      echo "proveo/claudecode-sol"
      ;;
    cursor)
      echo "proveo/cursor"
      ;;
    # Maintainer build/deploy names (not in the consumer TARGETS menu): the
    # shared harness base and the sidecar dependency images.
    base)
      echo "proveo/base"
      ;;
    egress-proxy)
      echo "proveo/egress-proxy"
      ;;
    mitmproxy)
      echo "proveo/mitmproxy"
      ;;
    *)
      print_error "No image name mapping for target: $target"
      exit 1
      ;;
  esac
}

target_description() {
  local target="$1"
  case "$target" in
    cecli)
      echo "Cecli with baked-in Proveo defaults"
      ;;
    cecli-node)
      echo "Cecli with Node.js, pnpm, and Playwright"
      ;;
    claudecode)
      echo "Claude Code with MCP integrations"
      ;;
    claudecode-solo)
      echo "Claude Code without the MCP-integrated stack"
      ;;
    claudecode-sol)
      echo "Claude Code with the Solidity/security toolchain (Foundry, solc, semgrep)"
      ;;
    opencode)
      echo "opencode with baked-in Proveo defaults"
      ;;
    cursor)
      echo "Cursor CLI agent with policy-gated autonomy"
      ;;
    *)
      echo "Container target"
      ;;
  esac
}

ensure_docker_available() {
  if ! command -v docker >/dev/null 2>&1; then
    print_error "Docker is required but was not found."
    echo "Install Docker from:"
    echo "  https://docs.docker.com/get-docker/"
    exit 1
  fi
}

ensure_image_available() {
  local image="$1"
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    print_info "Docker image not found locally: $image"
    print_info "Attempting to pull $image ..."
    docker pull "$image"
  fi
}

default_claude_data_dir() {
  local scope_dir="$1"
  local candidate="$scope_dir/workspace/data"
  if [[ -d "$candidate" ]]; then
    echo "$candidate"
  fi
}

default_claude_output_dir() {
  local scope_dir="$1"
  echo "$scope_dir/reports"
}

run_claude_container() {
  local image="$1"
  local scope_dir="$2"
  shift 2
  local -a extra_args=("$@")

  local output_dir
  local data_dir
  output_dir="$(default_claude_output_dir "$scope_dir")"
  data_dir="$(default_claude_data_dir "$scope_dir" || true)"

  mkdir -p "$output_dir"

  local -a docker_args=(
    run -it --rm
    --user "$(id -u):$(id -g)"
    --cap-drop=ALL
    --security-opt=no-new-privileges:true
    --tmpfs /tmp:noexec,nosuid,size=100m
    --tmpfs /workspace/temp:noexec,nosuid,size=2g
    --pids-limit=512
    --network=bridge
    --add-host=host.docker.internal:127.0.0.1
    -v "$scope_dir:/workspace/input:ro"
    -v "$output_dir:/workspace/output:rw"
    -e "CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN:-}"
  )

  # Forward the developer's git identity for commit attribution
  proveo_git_identity_env_args
  docker_args+=(${PROVEO_GIT_IDENTITY_ARGS[@]+"${PROVEO_GIT_IDENTITY_ARGS[@]}"})

  if [[ -n "$data_dir" ]]; then
    docker_args+=(-v "$data_dir:/workspace/data:ro")
    echo "📚 Using reference data from: $data_dir"
  fi

  echo "🚀 Starting Claude Code..."
  echo "📁 Input: $scope_dir"
  echo "📊 Output: $output_dir"
  if [[ ${#extra_args[@]} -gt 0 ]]; then
    echo "🔧 Claude options: ${extra_args[*]}"
  fi
  echo ""

  # Append dind arguments if sidecar is active
  docker_args+=(${DIND_DOCKER_ARGS[@]+"${DIND_DOCKER_ARGS[@]}"})

  docker_args+=("$image")
  docker_args+=(${extra_args[@]+"${extra_args[@]}"})

  docker "${docker_args[@]}"
}

run_opencode() {
  local scope_dir="$1"
  shift
  local -a extra_args=("$@")

  local image
  image="$(image_name "opencode")"
  ensure_image_available "$image"

  # Run as the caller's host UID/GID (never root) so files written to mounts
  # come back owned by the developer, for any uid — not just 1000. Apply the
  # same capability/privilege hardening baseline as the claudecode runner so all
  # harnesses share one floor (this runner is also the DinD-capable one).
  local -a docker_args=(
    run -it --rm
    --user "$(id -u):$(id -g)"
    --cap-drop=ALL
    --security-opt=no-new-privileges:true
    --pids-limit=512
  )

  # Forward the developer's git identity for commit attribution
  proveo_git_identity_env_args
  docker_args+=(${PROVEO_GIT_IDENTITY_ARGS[@]+"${PROVEO_GIT_IDENTITY_ARGS[@]}"})

  local container_name
  if [[ "$scope_dir" == "$CURRENT_REPO_ROOT" ]]; then
    container_name="$(basename "$CURRENT_REPO_ROOT")-opencode"
    docker_args+=(--name "$container_name")
    docker_args+=(-v "$CURRENT_REPO_ROOT:/app" -w /app)
  elif [[ "$scope_dir" == "$CURRENT_REPO_ROOT/"* ]]; then
    local relative_scope
    relative_scope="${scope_dir#$CURRENT_REPO_ROOT/}"

    container_name="$(basename "$CURRENT_REPO_ROOT")-${relative_scope//\//-}-opencode"
    docker_args+=(--name "$container_name")
    docker_args+=(-v "$scope_dir:/app/$relative_scope" -v "$CURRENT_REPO_ROOT/.git:/app/.git" -w /app)

    for root_file in .env AGENTS.md CONVENTIONS.md CLAUDE.md opencode.json opencode.jsonc package.json pnpm-workspace.yaml pnpm-lock.yaml package-lock.json yarn.lock turbo.json nx.json; do
      if [[ -e "$CURRENT_REPO_ROOT/$root_file" && ! -e "$scope_dir/$root_file" ]]; then
        docker_args+=(-v "$CURRENT_REPO_ROOT/$root_file:/app/$root_file:ro")
      fi
    done

    if [[ -d "$CURRENT_REPO_ROOT/.opencode" && ! -e "$scope_dir/.opencode" ]]; then
      docker_args+=(-v "$CURRENT_REPO_ROOT/.opencode:/app/.opencode:ro")
    fi

    if [[ -f "$scope_dir/.env" && ! -e "$CURRENT_REPO_ROOT/.env" ]]; then
      docker_args+=(-v "$scope_dir/.env:/app/.env:ro")
    fi
  else
    container_name="$(basename "$scope_dir")-opencode"
    docker_args+=(--name "$container_name")
    docker_args+=(-v "$scope_dir:/app" -w /app)
  fi

  docker rm -f "$container_name" >/dev/null 2>&1 || true

  # Append dind arguments if sidecar is active
  docker_args+=(${DIND_DOCKER_ARGS[@]+"${DIND_DOCKER_ARGS[@]}"})

  docker_args+=("$image")
  docker_args+=(${extra_args[@]+"${extra_args[@]}"})

  docker "${docker_args[@]}"
}

run_cursor() {
  local scope_dir="$1"
  shift
  local -a extra_args=("$@")

  local image
  image="$(image_name "cursor")"
  ensure_image_available "$image"

  if [[ -z "${CURSOR_API_KEY:-}" ]]; then
    printf "⚠️  CURSOR_API_KEY not set. Create one at cursor.com/dashboard → API Keys.\n" >&2
  fi

  # Same hardening baseline as the other runners: caller's UID/GID, no caps,
  # no privilege escalation, bounded pids.
  local -a docker_args=(
    run -it --rm
    --user "$(id -u):$(id -g)"
    --cap-drop=ALL
    --security-opt=no-new-privileges:true
    --pids-limit=512
  )

  # Forward the API key by NAME only — docker reads the value from this shell's
  # environment, so the secret never appears on a process argv.
  if [[ -n "${CURSOR_API_KEY:-}" ]]; then
    docker_args+=(-e CURSOR_API_KEY)
  fi

  # Forward the developer's git identity for commit attribution
  proveo_git_identity_env_args
  docker_args+=(${PROVEO_GIT_IDENTITY_ARGS[@]+"${PROVEO_GIT_IDENTITY_ARGS[@]}"})

  local container_name
  if [[ "$scope_dir" == "$CURRENT_REPO_ROOT" ]]; then
    container_name="$(basename "$CURRENT_REPO_ROOT")-cursor"
    docker_args+=(--name "$container_name")
    docker_args+=(-v "$CURRENT_REPO_ROOT:/app" -w /app)
  elif [[ "$scope_dir" == "$CURRENT_REPO_ROOT/"* ]]; then
    local relative_scope
    relative_scope="${scope_dir#$CURRENT_REPO_ROOT/}"

    container_name="$(basename "$CURRENT_REPO_ROOT")-${relative_scope//\//-}-cursor"
    docker_args+=(--name "$container_name")
    docker_args+=(-v "$scope_dir:/app/$relative_scope" -v "$CURRENT_REPO_ROOT/.git:/app/.git" -w /app)

    for root_file in .env AGENTS.md CONVENTIONS.md CLAUDE.md .cursorrules package.json pnpm-workspace.yaml pnpm-lock.yaml package-lock.json yarn.lock turbo.json nx.json; do
      if [[ -e "$CURRENT_REPO_ROOT/$root_file" && ! -e "$scope_dir/$root_file" ]]; then
        docker_args+=(-v "$CURRENT_REPO_ROOT/$root_file:/app/$root_file:ro")
      fi
    done

    if [[ -d "$CURRENT_REPO_ROOT/.cursor" && ! -e "$scope_dir/.cursor" ]]; then
      docker_args+=(-v "$CURRENT_REPO_ROOT/.cursor:/app/.cursor:ro")
    fi

    if [[ -f "$scope_dir/.env" && ! -e "$CURRENT_REPO_ROOT/.env" ]]; then
      docker_args+=(-v "$scope_dir/.env:/app/.env:ro")
    fi
  else
    container_name="$(basename "$scope_dir")-cursor"
    docker_args+=(--name "$container_name")
    docker_args+=(-v "$scope_dir:/app" -w /app)
  fi

  docker rm -f "$container_name" >/dev/null 2>&1 || true

  docker_args+=("$image")
  docker_args+=(${extra_args[@]+"${extra_args[@]}"})

  docker "${docker_args[@]}"
}

run_cecli() {
  local target="$1"
  local scope_dir="$2"
  shift 2
  local -a extra_args=("$@")

  local image
  local output_dir
  image="$(image_name "$target"):latest"
  output_dir="$scope_dir/reports"
  mkdir -p "$output_dir"
  ensure_image_available "$image"

  local container_name
  container_name="$(basename "$scope_dir")-$target"

  docker rm -f "$container_name" >/dev/null 2>&1 || true

  local -a docker_args=(
    run -it --rm
    --name "$container_name"
    # Run as the caller's host UID/GID (never root) so files written to the
    # mounted workspace come back owned by the developer, for any uid.
    --user "$(id -u):$(id -g)"
    # Capability/privilege hardening baseline, matching the claudecode runner.
    --cap-drop=ALL
    --security-opt=no-new-privileges:true
    --pids-limit=512
    -e "CECLI_HOME=/app/.cecli"
  )

  # Forward the developer's git identity for commit attribution
  proveo_git_identity_env_args
  docker_args+=(${PROVEO_GIT_IDENTITY_ARGS[@]+"${PROVEO_GIT_IDENTITY_ARGS[@]}"})

  docker_args+=(
    -e "CECLI_INSTALL_NODE_DEPS=${CECLI_INSTALL_NODE_DEPS:-0}"
    -v "$scope_dir:/app"
    -v "$output_dir:/app/output:rw"
    -w /app
  )

  # Append dind arguments if sidecar is active
  docker_args+=(${DIND_DOCKER_ARGS[@]+"${DIND_DOCKER_ARGS[@]}"})

  docker_args+=("$image")
  docker_args+=(${extra_args[@]+"${extra_args[@]}"})

  docker "${docker_args[@]}"
}

run_target() {
  local target="$1"
  shift
  local -a extra_args=("$@")
  local scope_dir=""

  # The installed CLI runs containers directly on the default Docker bridge; it
  # does NOT ship the Squid/mitmproxy egress topology (that is orchestrated by
  # the harness runner, defs/claudecode/run.sh). Intercept --egress-mode here so
  # a request for network enforcement FAILS CLOSED rather than being silently
  # forwarded to the harness as an unknown flag while the container runs with
  # full open egress — silently downgrading to open is a false sense of security.
  local egress_mode=""
  local -a passthrough_args=()
  local ea_i=0
  while [[ $ea_i -lt ${#extra_args[@]} ]]; do
    case "${extra_args[$ea_i]}" in
      --egress-mode)
        egress_mode="${extra_args[$((ea_i + 1))]:-}"
        ea_i=$((ea_i + 2))
        ;;
      --egress-mode=*)
        egress_mode="${extra_args[$ea_i]#*=}"
        ea_i=$((ea_i + 1))
        ;;
      *)
        passthrough_args+=("${extra_args[$ea_i]}")
        ea_i=$((ea_i + 1))
        ;;
    esac
  done
  extra_args=(${passthrough_args[@]+"${passthrough_args[@]}"})

  case "$egress_mode" in
    ""|open)
      : # open egress is the only mode the installed CLI can honor
      ;;
    proxy|firewall)
      print_error "--egress-mode '$egress_mode' is not available in the installed proveo CLI."
      echo "   The Squid/mitmproxy egress topology is orchestrated by the harness runner." >&2
      echo "   Run it from the proveo source tree: defs/claudecode/run.sh --egress-mode $egress_mode" >&2
      exit 1
      ;;
    *)
      print_error "Unknown --egress-mode '$egress_mode' (expected: open, proxy, firewall)."
      exit 1
      ;;
  esac

  ensure_docker_available

  scope_dir="$(choose_scope "$target")"

  # Sibling DinD sidecar dynamic provisioning
  local dind_name=""
  local use_dind=false
  export DIND_DOCKER_ARGS=()

  # Only targets whose image ships a docker client can use the sidecar; for
  # every other target a sidecar would be a wasted privileged container with an
  # unusable DOCKER_HOST. Keep this in sync with the images that install a
  # docker client (see defs/opencode/Dockerfile).
  local dind_capable=false
  case "$target" in
    opencode) dind_capable=true ;;
  esac

  if [[ "$dind_capable" == "true" && -n "$scope_dir" ]]; then
    # Dynamically build prune args from nearest .gitignore (traversing up from scope_dir)
    local -a prune_args=("-name" ".git")
    local gitignore_dir="$scope_dir"
    while [[ -n "$gitignore_dir" && "$gitignore_dir" != "/" ]]; do
      if [[ -f "$gitignore_dir/.gitignore" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
          line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
          if [[ -z "$line" || "$line" == "#"* || "$line" == "!"* ]]; then
            continue
          fi
          # find's -prune matches a directory basename only, so we can only
          # use plain directory-name entries. Strip the dir markers, then skip
          # anything with a path separator or a glob metacharacter rather than
          # mangling it (e.g. "*.log" -> ".log") into a pattern that misfires.
          local clean="${line%/}"   # trailing slash = dir marker
          clean="${clean#/}"        # leading slash = repo-root anchor
          case "$clean" in
            ""|"."|".."|*/*|*"*"*|*"?"*|*"["*) continue ;;
          esac
          prune_args+=("-o" "-name" "$clean")
        done < "$gitignore_dir/.gitignore"
        break
      fi
      gitignore_dir="$(dirname "$gitignore_dir")"
    done

    # Check for Dockerfiles or Compose configurations in scope_dir up to maxdepth 5, pruning ignored dirs
    if find "$scope_dir" -maxdepth 5 \( "${prune_args[@]}" \) -prune \
        -o \( -name "Dockerfile" -o -name "docker-compose.yml" -o -name "docker-compose.yaml" -o -name "compose.yml" -o -name "compose.yaml" \) -print -quit 2>/dev/null | grep -q .; then
      if [[ "${PROVEO_DIND:-}" == "1" || "${OPENCODE_INSTALL_DIND:-}" == "1" ]]; then
        use_dind=true
      elif is_tty; then
        printf "\n🐳 %sDockerfiles or Compose configurations detected in the project scope.%s\n" "$BOLD$CYAN" "$RESET" >&2
        printf "Do you want to launch a sibling Docker-in-Docker (dind) container for local testing? [y/N] " >&2
        local response=""
        read -r -t 10 response </dev/tty || response="n"
        if [[ "$response" =~ ^[yY](es)?$ ]]; then
          use_dind=true
        fi
      fi
    fi
  fi

  if [[ "$use_dind" == "true" ]]; then
    dind_name="proveo-dind-${target}"
    print_info "Starting sibling Docker-in-Docker (dind) container: $dind_name"
    printf "⚠️  %sSecurity warning:%s this dind sidecar runs with --privileged and shares the\n" "$BOLD" "$RESET" >&2
    printf "            host kernel. Its Docker daemon is exposed to the harness over an\n" >&2
    printf "            unauthenticated tcp://docker:2375 socket, so any code the agent runs\n" >&2
    printf "            can launch further privileged containers and may be able to escape to\n" >&2
    printf "            the host. It also has read-write access to the shared path: %s\n" "$scope_dir" >&2
    printf "            Only enable it for project code you trust.\n\n" >&2

    # Clean existing sidecar with same name if any
    docker rm -f "$dind_name" >/dev/null 2>&1 || true

    # Launch pristine dind sidecar container, mounting the scope directory
    docker run --privileged -d \
      --name "$dind_name" \
      -e DOCKER_TLS_CERTDIR="" \
      -v "$scope_dir:/app" \
      docker:dind >/dev/null

    # Register host-side lifecycle trap to remove the sidecar on signal/exit.
    # The name is baked into the trap body (note the double quotes + %q) rather
    # than referenced as $dind_name: that variable is a function local and is
    # out of scope by the time the EXIT trap fires after run_target returns, so
    # a single-quoted trap would expand to an empty name and leak the
    # privileged container.
    trap "docker rm -f $(printf '%q' "$dind_name") >/dev/null 2>&1 || true" EXIT INT TERM

    # Construct the global dind link/network and socket redirection parameters
    export DIND_DOCKER_ARGS=(
      --link "$dind_name":docker
      -e DOCKER_HOST=tcp://docker:2375
      -e DOCKER_TLS_VERIFY=""
    )
  fi

  case "$target" in
    cecli|cecli-node)
      run_cecli "$target" "$scope_dir" ${extra_args[@]+"${extra_args[@]}"}
      ;;
    claudecode|claudecode-solo|claudecode-sol)
      run_claude_container "$(image_name "$target")" "$scope_dir" ${extra_args[@]+"${extra_args[@]}"}
      ;;
    opencode)
      run_opencode "$scope_dir" ${extra_args[@]+"${extra_args[@]}"}
      ;;
    cursor)
      run_cursor "$scope_dir" ${extra_args[@]+"${extra_args[@]}"}
      ;;
    *)
      print_error "Unsupported run target: $target"
      exit 1
      ;;
  esac
}