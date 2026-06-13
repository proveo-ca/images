#!/usr/bin/env bash
# Maintainer builder for proveo CLI

find_script_in_dir() {
  local dir="$1"
  shift
  local script_name
  for script_name in "$@"; do
    if [[ -f "$dir/$script_name" ]]; then
      echo "$dir/$script_name"
      return 0
    fi
  done
  return 1
}

ensure_image_available() {
  local image="$1"
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    print_error "Docker image not found locally: $image"
    print_info "Build it first with: bin/proveo build ${2:-<target>} --tag ${DEFAULT_TAG}"
    exit 1
  fi
}

build_target() {
  local target="$1"
  local tag="$2"
  local no_cache="${3:-}"
  local dir
  dir="$(target_dir "$target")"

  local build_script=""
  build_script="$(find_script_in_dir "$dir" build.sh build.bash 2>/dev/null || true)"

  if [[ -n "$build_script" ]]; then
    print_info "Building $target with tag $tag via $(basename "$build_script")..."
    (
      cd "$dir"
      case "$target" in
        claudecode)
          if [[ -n "$no_cache" ]]; then
            "$build_script" --variant mcp --tag "$tag" --no-cache
          else
            "$build_script" --variant mcp --tag "$tag"
          fi
          ;;
        claudecode-solo)
          if [[ -n "$no_cache" ]]; then
            "$build_script" --variant solo --tag "$tag" --no-cache
          else
            "$build_script" --variant solo --tag "$tag"
          fi
          ;;
        *)
          if [[ -n "$no_cache" ]]; then
            "$build_script" --no-cache
          else
            "$build_script"
          fi
          ;;
      esac
    )

    case "$target" in
      cecli)
        if [[ "$tag" != "$DEFAULT_TAG" ]]; then
          docker tag "$(image_name cecli):latest" "$(image_name cecli):$tag"
        fi
        ensure_image_available "$(image_name cecli):$tag" "$target"
        print_success "Built $(image_name cecli):$tag"
        ;;
      cecli-node)
        if [[ "$tag" != "$DEFAULT_TAG" ]]; then
          docker tag "$(image_name cecli-node):latest" "$(image_name cecli-node):$tag"
        else
          true
        fi
        ensure_image_available "$(image_name cecli-node):$tag" "$target"
        print_success "Built $(image_name cecli-node):$tag"
        ;;
      *)
        if docker image inspect "$(image_name "$target")" >/dev/null 2>&1; then
          docker tag "$(image_name "$target")" "$(image_name "$target"):$tag"
        fi
        ensure_image_available "$(image_name "$target"):$tag" "$target"
        print_success "Built $(image_name "$target"):$tag"
        ;;
    esac
    return 0
  fi

  print_info "Building $target with tag $tag via docker build fallback..."
  docker build ${no_cache:+$no_cache} -t "$(image_name "$target"):$tag" -f "$dir/Dockerfile" "$REPO_ROOT"
  print_success "Built $(image_name "$target"):$tag"
}
