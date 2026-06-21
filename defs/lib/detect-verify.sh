#!/usr/bin/env bash
# detect-verify.sh
# Shared verification command discovery for coding harnesses.
# Outputs lines: <category>|<command>
# Categories: test, lint, build, typecheck, fmt

detect_verify_commands() {
  local root="${1:-$(pwd)}"
  [[ -d "$root" ]] || return 0

  local node_runner="npm run"
  local node_test="npm test"
  if [[ -f "$root/pnpm-lock.yaml" ]]; then
    node_runner="pnpm"
    node_test="pnpm test"
  elif [[ -f "$root/yarn.lock" ]]; then
    node_runner="yarn"
    node_test="yarn test"
  fi

  # Node / pnpm / npm / yarn
  if [[ -f "$root/package.json" ]]; then
    if command -v jq >/dev/null 2>&1; then
      local scripts
      scripts=$(jq -r '.scripts // {} | keys[]' "$root/package.json" 2>/dev/null || true)
      echo "$scripts" | grep -qE '^test$' && echo "test|$node_test"
      echo "$scripts" | grep -qE '^lint$' && echo "lint|$node_runner lint"
      echo "$scripts" | grep -qE '^build$' && echo "build|$node_runner build"
      echo "$scripts" | grep -qE '^typecheck$' && echo "typecheck|$node_runner typecheck"
      echo "$scripts" | grep -qE '^(fmt|format)$' && echo "fmt|$node_runner fmt"
    else
      # Fallback without jq
      grep -q '"test"' "$root/package.json" && echo "test|$node_test"
      grep -q '"lint"' "$root/package.json" && echo "lint|$node_runner lint"
      grep -q '"build"' "$root/package.json" && echo "build|$node_runner build"
    fi
  fi

  # Python
  if [[ -f "$root/pyproject.toml" || -f "$root/setup.py" || -f "$root/requirements.txt" ]]; then
    if command -v pytest >/dev/null 2>&1 || python3 -c "import pytest" 2>/dev/null; then
      echo "test|pytest"
    fi
    if command -v ruff >/dev/null 2>&1; then
      echo "lint|ruff check ."
    fi
    if command -v mypy >/dev/null 2>&1; then
      echo "typecheck|mypy ."
    fi
  fi

  # Go
  if [[ -f "$root/go.mod" ]]; then
    echo "test|go test ./..."
    echo "build|go build ./..."
  fi

  # Rust
  if [[ -f "$root/Cargo.toml" ]]; then
    echo "test|cargo test"
    echo "build|cargo build"
    echo "lint|cargo clippy"
  fi

  # Docker
  if [[ -f "$root/Dockerfile" || -f "$root/docker-compose.yml" ]]; then
    echo "build|docker build ."
  fi
}
