#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/test_harness_contracts.sh"
"$SCRIPT_DIR/../claudecode/tests/test_egress.sh"
