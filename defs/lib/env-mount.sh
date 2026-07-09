#!/usr/bin/env bash
# Resolve a host .env path for Docker bind mounts / broker ingestion.
#
# Security: provider secrets in .env must not reach the agent in proxy/firewall
# mode. Mount the real file only in broker mode; in proxy/firewall mask visible
# .env paths with /dev/null and feed keys to the broker from the host instead.

# proveo_resolve_env_mount_source <input_dir> [repo_root]
# Prints the resolved absolute path to a regular .env file, or returns 1.
proveo_resolve_env_mount_source() {
  local input_dir="${1:?input_dir required}"
  local repo_root="${2:-}"
  local candidate resolved

  for candidate in "$input_dir/.env" ${repo_root:+"$repo_root/.env"}; do
    [[ -e "$candidate" ]] || continue
    resolved="$(python3 - "$candidate" <<'PY'
import os
import sys

path = sys.argv[1]
try:
    path = os.path.realpath(path)
except OSError:
    sys.exit(1)
if os.path.isfile(path):
    print(path)
PY
)" || continue
    [[ -n "$resolved" ]] || continue
    printf '%s\n' "$resolved"
    return 0
  done
  return 1
}

# proveo_env_file_get <key> <env_file>
# Prints the value for KEY from a KEY=VALUE env file (no shell sourcing).
proveo_env_file_get() {
  local key="${1:?key required}"
  local env_file="${2:?env_file required}"
  [[ -f "$env_file" ]] || return 1
  python3 - "$key" "$env_file" <<'PY'
import sys

key, path = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[7:].lstrip()
            if "=" not in line:
                continue
            k, _, v = line.partition("=")
            if k.strip() != key:
                continue
            v = v.strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                v = v[1:-1]
            print(v)
            raise SystemExit(0)
except OSError:
    raise SystemExit(1)
raise SystemExit(1)
PY
}

# proveo_append_env_mount_args <array_name> <input_dir> [repo_root] [egress_mode] [relative_scope]
# broker (default arg when omitted): overlay resolved .env at /app/.env:ro when present.
# proxy|firewall: do not mount secrets; mask .env paths that a bind would expose.
# relative_scope: monorepo subdir under /app (e.g. apps/web); empty => input at /app.
proveo_append_env_mount_args() {
  local -n _out_arr=$1
  local input_dir="${2:?input_dir required}"
  local repo_root="${3:-}"
  local mode="${4:-broker}"
  local relative_scope="${5:-}"
  local resolved masked=0

  case "$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')" in
    proxy|firewall)
      if [[ -n "$relative_scope" ]]; then
        if [[ -e "$input_dir/.env" ]]; then
          _out_arr+=(-v "/dev/null:/app/${relative_scope}/.env:ro")
          masked=1
        fi
        if [[ -n "$repo_root" && -e "$repo_root/.env" ]]; then
          _out_arr+=(-v "/dev/null:/app/.env:ro")
          masked=1
        fi
      elif [[ -e "$input_dir/.env" || ( -n "$repo_root" && -e "$repo_root/.env" ) ]]; then
        _out_arr+=(-v "/dev/null:/app/.env:ro")
        masked=1
      fi
      if (( masked )); then
        echo "🔒 Masking .env in agent (egress mode $mode — secrets stay on host / broker)" >&2
      fi
      return 0
      ;;
  esac

  resolved="$(proveo_resolve_env_mount_source "$input_dir" "$repo_root")" || return 0
  _out_arr+=(-v "$resolved:/app/.env:ro")
}
