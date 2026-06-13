#!/usr/bin/env bash
# Maintainer runners for proveo CLI

target_dir() {
  local target="$1"
  case "$target" in
    aider-node)
      echo "$REPO_ROOT/defs/aider-node"
      ;;
    cecli|cecli-node)
      echo "$REPO_ROOT/defs/cecli"
      ;;
    charles-proxy)
      echo "$REPO_ROOT/defs/charles-proxy"
      ;;
    opencode)
      echo "$REPO_ROOT/defs/opencode"
      ;;
    claudecode|claudecode-solo)
      echo "$REPO_ROOT/defs/claudecode"
      ;;
    *)
      print_error "No directory mapping for target: $target"
      exit 1
      ;;
  esac
}

run_target() {
  local target="$1"
  local tag="$2"
  shift 2
  local -a extra_args=("$@")
  local scope_dir

  case "$target" in
    cecli)
      scope_dir="$(choose_scope "$target")"
      "$(target_dir cecli)/run.sh" --image "$(image_name cecli):$tag" --input-dir "$scope_dir" --repo-root "$REPO_ROOT" -- ${extra_args[@]+"${extra_args[@]}"}
      ;;
    cecli-node)
      scope_dir="$(choose_scope "$target")"
      "$(target_dir cecli)/run.sh" --image "$(image_name cecli-node):$tag" --input-dir "$scope_dir" --repo-root "$REPO_ROOT" -- ${extra_args[@]+"${extra_args[@]}"}
      ;;
    claudecode)
      scope_dir="$(choose_scope "$target")"
      "$(target_dir claudecode)/run.sh" --variant mcp --image "$(image_name claudecode):$tag" --input-dir "$scope_dir" -- ${extra_args[@]+"${extra_args[@]}"}
      ;;
    claudecode-solo)
      scope_dir="$(choose_scope "$target")"
      "$(target_dir claudecode)/run.sh" --variant solo --image "$(image_name claudecode-solo):$tag" --input-dir "$scope_dir" -- ${extra_args[@]+"${extra_args[@]}"}
      ;;
    opencode)
      scope_dir="$(choose_scope "$target")"
      "$(target_dir opencode)/run.sh" --image "$(image_name opencode):$tag" --input-dir "$scope_dir" -- ${extra_args[@]+"${extra_args[@]}"}
      ;;
    aider-node)
      scope_dir="$(choose_scope "$target")"
      "$(target_dir aider-node)/run.sh" --image "$(image_name aider-node):$tag" --input-dir "$scope_dir" --repo-root "$REPO_ROOT" -- ${extra_args[@]+"${extra_args[@]}"}
      ;;
    charles-proxy)
      "$(target_dir charles-proxy)/run.sh" --image "$(image_name charles-proxy):$tag" ${extra_args[@]+"${extra_args[@]}"}
      ;;
    *)
      print_error "Unsupported run target: $target"
      exit 1
      ;;
  esac
}

debug_target() {
  local target="$1"
  local tag="$2"
  shift 2
  local -a extra_args=("$@")
  local scope_dir

  case "$target" in
    aider-node)
      scope_dir="$(choose_scope "$target")"
      "$(target_dir aider-node)/debug.sh" --image "$(image_name aider-node):$tag" --input-dir "$scope_dir" --repo-root "$REPO_ROOT" -- ${extra_args[@]+"${extra_args[@]}"}
      ;;
    claudecode)
      scope_dir="$(choose_scope "$target")"
      PROVEO_CLAUDECODE_IMAGE="$(image_name claudecode):$tag" "$(target_dir claudecode)/mcp/debug.sh" --input-dir "$scope_dir" --output-dir "$(default_claude_output_dir "$scope_dir")" ${extra_args[@]+"${extra_args[@]}"}
      ;;
    claudecode-solo)
      scope_dir="$(choose_scope "$target")"
      PROVEO_CLAUDECODE_SOLO_IMAGE="$(image_name claudecode-solo):$tag" "$(target_dir claudecode)/solo/debug.sh" --input-dir "$scope_dir" --output-dir "$(default_claude_output_dir "$scope_dir")" ${extra_args[@]+"${extra_args[@]}"}
      ;;
    charles-proxy)
      "$(target_dir charles-proxy)/debug.sh" --image "$(image_name charles-proxy):$tag" ${extra_args[@]+"${extra_args[@]}"}
      ;;
    *)
      print_error "Unsupported debug target: $target"
      exit 1
      ;;
  esac
}
