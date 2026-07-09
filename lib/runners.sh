#!/usr/bin/env bash
# Maintainer runners for proveo CLI

# Maintainer-only image targets around the consumer TARGETS the mise tasks
# already sourced from bin/proveo: the shared harness base FIRST (every
# Node-based harness builds FROM it, so `all` must build it before them) and
# the sidecar dependency images after. Everything with a defs/**/build.sh must
# ship through `mise build` / `mise deploy` so consumers can pull it from
# Docker Hub — the harness contract test derives that invariant from the
# filesystem.
TARGETS=("base" "${TARGETS[@]}" "egress-proxy" "mitmproxy")

target_dir() {
  local target="$1"
  case "$target" in
    base)
      echo "$REPO_ROOT/defs/base"
      ;;
    cecli|cecli-node)
      echo "$REPO_ROOT/defs/cecli"
      ;;
    opencode)
      echo "$REPO_ROOT/defs/opencode"
      ;;
    claudecode|claudecode-solo|claudecode-sol)
      echo "$REPO_ROOT/defs/claudecode"
      ;;
    cursor)
      echo "$REPO_ROOT/defs/cursor"
      ;;
    egress-proxy)
      echo "$REPO_ROOT/defs/sidecars/egress-proxy"
      ;;
    mitmproxy)
      echo "$REPO_ROOT/defs/sidecars/mitmproxy"
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
      # No leading `--`: egress flags (--egress-mode/--local-model/...) must reach
      # run.sh's own option parser, not be forwarded straight to the harness.
      "$(target_dir claudecode)/run.sh" --variant mcp --image "$(image_name claudecode):$tag" --input-dir "$scope_dir" ${extra_args[@]+"${extra_args[@]}"}
      ;;
    claudecode-solo)
      scope_dir="$(choose_scope "$target")"
      "$(target_dir claudecode)/run.sh" --variant solo --image "$(image_name claudecode-solo):$tag" --input-dir "$scope_dir" ${extra_args[@]+"${extra_args[@]}"}
      ;;
    opencode)
      scope_dir="$(choose_scope "$target")"
      "$(target_dir opencode)/run.sh" --image "$(image_name opencode):$tag" --input-dir "$scope_dir" -- ${extra_args[@]+"${extra_args[@]}"}
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
    claudecode)
      scope_dir="$(choose_scope "$target")"
      # Egress consolidated per-variant debug.sh into `run.sh --shell`.
      "$(target_dir claudecode)/run.sh" --variant mcp --image "$(image_name claudecode):$tag" --input-dir "$scope_dir" --output-dir "$(default_claude_output_dir "$scope_dir")" --shell -- ${extra_args[@]+"${extra_args[@]}"}
      ;;
    claudecode-solo)
      scope_dir="$(choose_scope "$target")"
      "$(target_dir claudecode)/run.sh" --variant solo --image "$(image_name claudecode-solo):$tag" --input-dir "$scope_dir" --output-dir "$(default_claude_output_dir "$scope_dir")" --shell -- ${extra_args[@]+"${extra_args[@]}"}
      ;;
    *)
      print_error "Unsupported debug target: $target"
      exit 1
      ;;
  esac
}
