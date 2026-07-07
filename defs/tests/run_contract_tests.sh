#!/usr/bin/env bash
# SPEC: _spec/tests/00-testing-overview.puml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Provider detection + the Squid write-pin ACL now live in Go (internal/provider,
# internal/egress); egress.sh delegates to the `proveo-egress` binary. Build it
# once so the contract tests below exercise that real path (live single source).
if command -v go >/dev/null 2>&1; then
  _bin_dir="$(mktemp -d)"
  ( cd "$REPO_ROOT" && go build -o "$_bin_dir/proveo-egress" ./cmd/proveo-egress )
  export PROVEO_EGRESS_BIN="$_bin_dir/proveo-egress"
  trap 'rm -rf "$_bin_dir"' EXIT
else
  echo "⚠️  go toolchain not found; egress.sh will fall back to 'go run' per call" >&2
fi

"$SCRIPT_DIR/test_harness_contracts.sh"
"$SCRIPT_DIR/../claudecode/tests/test_egress.sh"
