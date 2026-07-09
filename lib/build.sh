#!/usr/bin/env bash
# Maintainer builder for proveo CLI
# (ensure_image_available lives in lib/helpers.sh — shared with the deploy task.)

build_target() {
  local target="$1"
  local tag="$2"
  local no_cache="${3:-}"
  local dir
  dir="$(reg_dir "$target")"

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
        claudecode-sol)
          if [[ -n "$no_cache" ]]; then
            "$build_script" --variant sol --tag "$tag" --no-cache
          else
            "$build_script" --variant sol --tag "$tag"
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
          docker tag "$(reg_image cecli):latest" "$(reg_image cecli):$tag"
        fi
        ensure_image_available "$(reg_image cecli):$tag" "$target"
        print_success "Built $(reg_image cecli):$tag"
        ;;
      cecli-node)
        if [[ "$tag" != "$DEFAULT_TAG" ]]; then
          docker tag "$(reg_image cecli-node):latest" "$(reg_image cecli-node):$tag"
        else
          true
        fi
        ensure_image_available "$(reg_image cecli-node):$tag" "$target"
        print_success "Built $(reg_image cecli-node):$tag"
        ;;
      *)
        if docker image inspect "$(reg_image "$target")" >/dev/null 2>&1; then
          docker tag "$(reg_image "$target")" "$(reg_image "$target"):$tag"
        fi
        ensure_image_available "$(reg_image "$target"):$tag" "$target"
        print_success "Built $(reg_image "$target"):$tag"
        ;;
    esac
    return 0
  fi

  print_info "Building $target with tag $tag via docker build fallback..."
  docker build ${no_cache:+$no_cache} -t "$(reg_image "$target"):$tag" -f "$dir/Dockerfile" "$REPO_ROOT"
  print_success "Built $(reg_image "$target"):$tag"
}
