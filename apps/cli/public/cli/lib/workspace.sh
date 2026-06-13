#!/usr/bin/env bash
# Workspace / Monorepo scope helper module for proveo CLI

find_repo_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/pnpm-workspace.yaml" ]] || ( [[ -f "$dir/package.json" ]] && grep -Fq '"workspaces"' "$dir/package.json" ); then
      echo "$dir"
      return 0
    fi
    if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 && [[ "$dir" == "$(git -C "$dir" rev-parse --show-toplevel)" ]]; then
      break
    fi
    dir="$(dirname "$dir")"
  done

  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
  else
    pwd
  fi
}

is_monorepo() {
  [[ -f "$CURRENT_REPO_ROOT/pnpm-workspace.yaml" ]] || \
  [[ -f "$CURRENT_REPO_ROOT/turbo.json" ]] || \
  [[ -f "$CURRENT_REPO_ROOT/nx.json" ]] || \
  [[ -f "$CURRENT_REPO_ROOT/lerna.json" ]] || \
  ( [[ -f "$CURRENT_REPO_ROOT/package.json" ]] && grep -Fq '"workspaces"' "$CURRENT_REPO_ROOT/package.json" )
}

parse_package_json_workspaces() {
  local package_file="$CURRENT_REPO_ROOT/package.json"
  [[ -f "$package_file" ]] || return 0

  awk '
    BEGIN { in_workspaces = 0 }
    /"workspaces"[[:space:]]*:[[:space:]]*\[/ { in_workspaces = 1; }
    in_workspaces == 1 {
      s = $0
      while (match(s, /"[^"]*"/)) {
        val = substr(s, RSTART+1, RLENGTH-2)
        if (val != "workspaces") {
          print val
        }
        s = substr(s, RSTART+RLENGTH)
      }
      if ($0 ~ /\]/) {
        in_workspaces = 0
      }
    }
  ' "$package_file"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

parse_pnpm_workspace_globs() {
  local workspace_file="$CURRENT_REPO_ROOT/pnpm-workspace.yaml"
  [[ -f "$workspace_file" ]] || return 0

  awk '
    BEGIN { in_packages = 0 }
    /^[[:space:]]*packages:[[:space:]]*$/ { in_packages = 1; next }
    in_packages == 1 {
      if ($0 ~ /^[^[:space:]-]/) exit
      if ($0 ~ /^[[:space:]]*-[[:space:]]*/) {
        sub(/^[[:space:]]*-[[:space:]]*/, "", $0)
        gsub(/^["'\''"]|["'\''"]$/, "", $0)
        print $0
      }
    }
  ' "$workspace_file"
}

discover_workspaces() {
  local glob
  local candidate
  local -a globs=()

  while IFS= read -r glob; do
    glob="$(trim "$glob")"
    [[ -n "$glob" ]] || continue
    globs+=("$glob")
  done < <( { parse_pnpm_workspace_globs; parse_package_json_workspaces; } | awk '!seen[$0]++' )

  if [[ ${#globs[@]} -eq 0 ]] && is_monorepo; then
    globs=("apps/*" "packages/*" "libs/*" "projects/*")
  fi

  if [[ ${#globs[@]} -eq 0 ]]; then
    return 0
  fi

  (
    shopt -s nullglob
    shopt -s globstar 2>/dev/null || true
    cd "$CURRENT_REPO_ROOT"

    for glob in "${globs[@]}"; do
      for candidate in $glob; do
        [[ -d "$candidate" ]] || continue
        if [[ -f "$candidate/package.json" || -f "$candidate/project.json" || -f "$candidate/go.mod" || -f "$candidate/Cargo.toml" ]]; then
          printf '%s\n' "$candidate"
        fi
      done
    done
  ) | awk '!seen[$0]++'
}

choose_scope() {
  local target="$1"
  local -a workspaces=()
  local selection
  local i

  if ! is_ai_harness "$target"; then
    echo "$PWD"
    return 0
  fi

  if ! is_monorepo; then
    echo "$PWD"
    return 0
  fi

  while IFS= read -r workspace; do
    [[ -n "$workspace" ]] || continue
    workspaces+=("$workspace")
  done < <(discover_workspaces)

  if [[ ${#workspaces[@]} -eq 0 ]]; then
    echo "$PWD"
    return 0
  fi

  local default_scope="$PWD"
  local default_label
  if [[ "$PWD" == "$CURRENT_REPO_ROOT" ]]; then
    default_label="current directory (repo root)"
  elif [[ "$PWD" == "$CURRENT_REPO_ROOT/"* ]]; then
    default_label="current directory (${PWD#$CURRENT_REPO_ROOT/})"
  else
    default_label="current directory ($PWD)"
  fi

  if ! is_tty; then
    echo "$default_scope"
    return 0
  fi

  local -a scope_options=(
    "current directory ($default_label)"
    "repo root ($CURRENT_REPO_ROOT)"
  )

  for workspace in "${workspaces[@]}"; do
    scope_options+=("workspace: $workspace")
  done

  printf '\n%s%sSelect scope for %s:%s\n' "$BOLD" "$CYAN" "$RESET" >&2
  local choice=0
  tui_select "${scope_options[@]}" || choice=$?

  if [[ $choice -eq 255 ]]; then
    echo "$default_scope"
    return 0
  fi

  if [[ $choice -eq 0 ]]; then
    echo "$default_scope"
  elif [[ $choice -eq 1 ]]; then
    echo "$CURRENT_REPO_ROOT"
  else
    local selected_workspace="${workspaces[$((choice - 2))]}"
    echo "$CURRENT_REPO_ROOT/$selected_workspace"
  fi
}

container_name_for_scope() {
  local scope_dir="$1"
  local repo_name
  local scope_name

  repo_name="$(basename "$CURRENT_REPO_ROOT")"

  if [[ "$scope_dir" == "$CURRENT_REPO_ROOT" ]]; then
    echo "$repo_name"
    return 0
  fi

  scope_name="${scope_dir#$CURRENT_REPO_ROOT/}"
  scope_name="${scope_name//\//-}"
  echo "${repo_name}-${scope_name}"
}
