#!/usr/bin/env bash
# Docker target runners helper module for proveo CLI

image_name() {
  local target="$1"
  case "$target" in
    aider-node)
      echo "proveo/aider-node"
      ;;
    cecli)
      echo "proveo/cecli"
      ;;
    cecli-node)
      echo "proveo/cecli-node"
      ;;
    charles-proxy)
      echo "proveo/charles-proxy"
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
    *)
      print_error "No image name mapping for target: $target"
      exit 1
      ;;
  esac
}

target_description() {
  local target="$1"
  case "$target" in
    aider-node)
      echo "Aider with Node.js, pnpm, and Playwright"
      ;;
    cecli)
      echo "Cecli with baked-in Proveo defaults"
      ;;
    cecli-node)
      echo "Cecli with Node.js, pnpm, and Playwright"
      ;;
    charles-proxy)
      echo "Headless Charles Proxy utility container"
      ;;
    claudecode)
      echo "Claude Code with MCP integrations"
      ;;
    claudecode-solo)
      echo "Claude Code without the MCP-integrated stack"
      ;;
    opencode)
      echo "opencode with baked-in Proveo defaults"
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

run_aider_node() {
  local scope_dir="$1"
  shift
  local -a extra_args=("$@")

  local image
  local repo_name
  image="$(image_name "aider-node")"
  ensure_image_available "$image"

  repo_name="$(container_name_for_scope "$scope_dir")"

  local -a docker_args=(run -it --rm --name "$repo_name")

  if [[ "$scope_dir" == "$CURRENT_REPO_ROOT" ]]; then
    print_info "Running aider-node at repo root"
    docker_args+=(-v "$CURRENT_REPO_ROOT:/app" -w /app)
  elif [[ "$scope_dir" != "$CURRENT_REPO_ROOT/"* ]]; then
    print_info "Running aider-node in current directory"
    docker_args+=(-v "$scope_dir:/app" -w /app)
  else
    local relative_scope
    relative_scope="${scope_dir#$CURRENT_REPO_ROOT/}"
    print_info "Running aider-node with monorepo workspace: $relative_scope"

    docker_args+=(
      -v "$scope_dir:/app/$relative_scope"
      -v "$CURRENT_REPO_ROOT/.git:/app/.git"
      -w /app
    )

    if [[ -f "$scope_dir/.aiderignore" ]]; then
      docker_args+=(-v "$scope_dir/.aiderignore:/app/.aiderignore")
    fi
  fi

  # Append dind arguments if sidecar is active
  docker_args+=(${DIND_DOCKER_ARGS[@]+"${DIND_DOCKER_ARGS[@]}"})

  docker_args+=("$image")
  docker_args+=(${extra_args[@]+"${extra_args[@]}"})

  docker "${docker_args[@]}"
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
    --cap-drop=ALL
    --security-opt=no-new-privileges:true
    --tmpfs /tmp:noexec,nosuid,size=100m
    --tmpfs /workspace/temp:noexec,nosuid,size=2g
    --pids-limit=100
    --network=bridge
    --add-host=host.docker.internal:127.0.0.1
    -v "$scope_dir:/workspace/input:ro"
    -v "$output_dir:/workspace/output:rw"
    -e "CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN:-}"
  )

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

  local -a docker_args=(run -it --rm)

  if [[ "$scope_dir" == "$CURRENT_REPO_ROOT" ]]; then
    docker_args+=(--name "$(basename "$CURRENT_REPO_ROOT")-opencode")
    docker_args+=(-v "$CURRENT_REPO_ROOT:/app" -w /app)
  elif [[ "$scope_dir" == "$CURRENT_REPO_ROOT/"* ]]; then
    local relative_scope
    relative_scope="${scope_dir#$CURRENT_REPO_ROOT/}"

    docker_args+=(--name "$(basename "$CURRENT_REPO_ROOT")-${relative_scope//\//-}-opencode")
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
    docker_args+=(--name "$(basename "$scope_dir")-opencode")
    docker_args+=(-v "$scope_dir:/app" -w /app)
  fi

  # Append dind arguments if sidecar is active
  docker_args+=(${DIND_DOCKER_ARGS[@]+"${DIND_DOCKER_ARGS[@]}"})

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

  local -a docker_args=(
    run -it --rm
    --name "$(basename "$scope_dir")-$target"
    -e "LOCAL_UID=$(id -u)"
    -e "LOCAL_GID=$(id -g)"
    -e "CECLI_HOME=/app/.cecli"
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

run_charles_proxy() {
  local image
  image="$(image_name "charles-proxy")"
  ensure_image_available "$image"

  local sessions_dir="$PWD/sessions"
  local config_dir="$PWD/config"

  mkdir -p "$sessions_dir" "$config_dir"

  print_info "Running charles-proxy on port 8888"
  docker run -it --rm \
    -p 8888:8888 \
    -v "$sessions_dir:/sessions" \
    -v "$config_dir:/config" \
    "$image"
}

run_target() {
  local target="$1"
  shift
  local -a extra_args=("$@")
  local scope_dir=""

  ensure_docker_available

  if [[ "$target" != "charles-proxy" ]]; then
    scope_dir="$(choose_scope "$target")"
  fi

  # Sibling DinD sidecar dynamic provisioning
  local dind_name=""
  local use_dind=false
  export DIND_DOCKER_ARGS=()

  if [[ -n "$scope_dir" ]]; then
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
          local clean="${line%/}"
          clean="${clean#\/}"
          clean="${clean#\*}"
          clean="${clean#\/}"
          if [[ -n "$clean" && "$clean" != "." && "$clean" != ".." ]]; then
            prune_args+=("-o" "-name" "$clean")
          fi
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
    printf "🔒 %sSecurity:%s This dind sidecar is a pristine, secure, and isolated container.\n" "$BOLD" "$RESET" >&2
    printf "            It has NO access to your host system outside of the shared path: %s\n\n" "$scope_dir" >&2

    # Clean existing sidecar with same name if any
    docker rm -f "$dind_name" >/dev/null 2>&1 || true

    # Launch pristine dind sidecar container, mounting the scope directory
    docker run --privileged -d \
      --name "$dind_name" \
      -e DOCKER_TLS_CERTDIR="" \
      -v "$scope_dir:/app" \
      docker:dind >/dev/null

    # Register host-side lifecycle trap to cleanly terminate sidecar when script exits
    trap 'docker rm -f "$dind_name" >/dev/null 2>&1' EXIT INT TERM

    # Construct the global dind link/network and socket redirection parameters
    export DIND_DOCKER_ARGS=(
      --link "$dind_name":docker
      -e DOCKER_HOST=tcp://docker:2375
      -e DOCKER_TLS_VERIFY=""
    )
  fi

  case "$target" in
    aider-node)
      run_aider_node "$scope_dir" ${extra_args[@]+"${extra_args[@]}"}
      ;;
    cecli|cecli-node)
      run_cecli "$target" "$scope_dir" ${extra_args[@]+"${extra_args[@]}"}
      ;;
    claudecode|claudecode-solo)
      run_claude_container "$(image_name "$target")" "$scope_dir" ${extra_args[@]+"${extra_args[@]}"}
      ;;
    opencode)
      run_opencode "$scope_dir" ${extra_args[@]+"${extra_args[@]}"}
      ;;
    charles-proxy)
      run_charles_proxy
      ;;
    *)
      print_error "Unsupported run target: $target"
      exit 1
      ;;
  esac
}