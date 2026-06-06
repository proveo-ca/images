#!/usr/bin/env bash
set -euo pipefail

FIREHOL_IPSET="${FIREHOL_IPSET:-firehol_level1}"
FIREHOL_SOURCE_URL="${FIREHOL_SOURCE_URL:-https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/${FIREHOL_IPSET}.netset}"
OUTPUT_DIR="${1:-${FIREHOL_OUTPUT_DIR:-$(pwd)/config}}"
OUTPUT_FILE="$OUTPUT_DIR/firehol-ipset.conf"

usage() {
  cat <<'EOF'
Usage:
  update-firehol-ipsets.sh [output-dir]

Fetches a FireHOL blocklist-ipsets netset and converts it into Squid ACLs.

Environment:
  FIREHOL_IPSET        FireHOL ipset name (default: firehol_level1)
  FIREHOL_SOURCE_URL   Override source URL
  FIREHOL_OUTPUT_DIR   Output directory when no argument is provided

Notes:
  - This does not install FireHOL or ipset kernel rules.
  - This is a Squid adaptation of a FireHOL IP list.
  - FireHOL docs warn that IP blocklists can have false positives; keep this
    optional and pair it with allowlists where needed.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$OUTPUT_DIR"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

curl -fsSL "$FIREHOL_SOURCE_URL" -o "$tmp"

{
  printf '# Generated from %s\n' "$FIREHOL_SOURCE_URL"
  printf '# FireHOL ipset: %s\n' "$FIREHOL_IPSET"
  printf '# Generated at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '# Review false-positive risk before enabling broad feeds.\n'
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line//[$'\t\r\n ']/}"
    [[ -n "$line" ]] || continue
    printf 'acl firehol_ipset dst %s\n' "$line"
  done <"$tmp"
  printf 'http_access deny firehol_ipset\n'
} >"$OUTPUT_FILE"

printf 'Wrote %s\n' "$OUTPUT_FILE"
