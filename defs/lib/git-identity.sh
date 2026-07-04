#!/usr/bin/env bash
# Shared wrapper helper: forward the developer's git identity (GIT_* env wins,
# else host git config) as `-e` pairs in PROVEO_GIT_IDENTITY_ARGS (bash 3.2-safe).
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
