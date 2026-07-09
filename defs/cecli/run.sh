#!/usr/bin/env bash
# Thin shim → proveo run.
# SPEC: _spec/usage.puml, _spec/components.puml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${PROVEO_BIN:-}" ]]; then
 if command -v proveo >/dev/null 2>&1; then
 PROVEO_BIN="$(command -v proveo)"
 elif [[ -x "$SCRIPT_DIR/../../bin/proveo" ]]; then
 PROVEO_BIN="$SCRIPT_DIR/../../bin/proveo"
 else
 PROVEO_BIN="proveo"
 fi
fi

TARGET="cecli-node"
ARGS=
while [[ $# -gt 0 ]]; do
 case "$1" in
 --python) TARGET="cecli"; shift ;;
 --node) TARGET="cecli-node"; shift ;;
 --image)
 [[ $# -ge 2 ]] || { echo "--image requires a value" >&2; exit 1; }
 ARGS+=(--image "$2"); shift 2 ;;
 --input-dir)
 [[ $# -ge 2 ]] || { echo "--input-dir requires a value" >&2; exit 1; }
 ARGS+=(--input "$2"); shift 2 ;;
 --output-dir)
 [[ $# -ge 2 ]] || { echo "--output-dir requires a value" >&2; exit 1; }
 ARGS+=(--output "$2"); shift 2 ;;
 --repo-root)
 [[ $# -ge 2 ]] || { echo "--repo-root requires a value" >&2; exit 1; }
 shift 2 ;;
 --egress-mode|--local-model)
 [[ $# -ge 2 ]] || { echo "$1 requires a value" >&2; exit 1; }
 ARGS+=("$1" "$2"); shift 2 ;;
 --shell|--print)
 ARGS+=("$1"); shift ;;
 --read-only)
 # Mount mode is manifest-driven; accept for flag compatibility.
 shift ;;
 -h|--help)
 exec "$PROVEO_BIN" run --help ;;
 --)
 shift; ARGS+=(-- "$@"); break ;;
 *)
 ARGS+=("$1"); shift ;;
 esac
done

# Image name may imply target when set via CECLI_IMAGE / --image proveo/cecli
if [[ -n "${CECLI_IMAGE:-}" && ${#ARGS[@]} -eq 0 ]]; then
 case "$CECLI_IMAGE" in
 *cecli:python*|*cecli:latest*|*/cecli|*/cecli:*) TARGET="cecli" ;;
 esac
fi

exec "$PROVEO_BIN" run "$TARGET" ${ARGS[@]+"${ARGS[@]}"}
