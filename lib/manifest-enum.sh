#!/usr/bin/env bash
# Enumerate harness targets/images from defs/*/harness.manifest (single registration).
# Used by maintainer mise + consumer CLI when the defs tree is present.
# Requires: REPO_ROOT or PROVEO_DEFS_DIR pointing at a tree that contains defs/.

proveo_defs_root() {
  if [[ -n "${PROVEO_DEFS_DIR:-}" ]]; then
    printf '%s\n' "$PROVEO_DEFS_DIR"
    return 0
  fi
  if [[ -n "${REPO_ROOT:-}" && -d "$REPO_ROOT/defs" ]]; then
    printf '%s\n' "$REPO_ROOT/defs"
    return 0
  fi
  return 1
}

# Print "target|image|description|defdir" lines for every images: key in every harness.manifest.
proveo_manifest_entries() {
  local defs root f name desc in_images key val defdir
  defs="$(proveo_defs_root)" || return 1
  root="$(cd "$defs/.." && pwd)"
  shopt -s nullglob
  for f in "$defs"/*/harness.manifest; do
    [[ -f "$f" ]] || continue
    defdir="$(dirname "$f")"
    name=""
    desc=""
    in_images=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      # strip comments
      line="${line%%#*}"
      # trim
      line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [[ -n "$line" ]] || continue
      case "$line" in
        name:*)
          name="${line#name:}"
          name="$(printf '%s' "$name" | sed -e 's/^[[:space:]]*//')"
          ;;
        description:*)
          desc="${line#description:}"
          desc="$(printf '%s' "$desc" | sed -e 's/^[[:space:]]*//')"
          ;;
        images:)
          in_images=1
          ;;
        workspace:*|env:*|egress:*|dind:*|stability:*)
          in_images=0
          ;;
        *)
          if (( in_images )); then
            # "  key: value" under images:
            if [[ "$line" == *:* ]]; then
              key="${line%%:*}"
              val="${line#*:}"
              key="$(printf '%s' "$key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
              val="$(printf '%s' "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
              [[ -n "$key" && -n "$val" ]] || continue
              printf '%s|%s|%s|%s\n' "$key" "$val" "$desc" "$defdir"
            fi
          fi
          ;;
      esac
    done < "$f"
  done
}

# Populate global arrays from manifests: MANIFEST_TARGETS, and associative maps via parallel arrays.
# Bash 3.2-safe (no declare -A).
proveo_load_manifest_targets() {
  MANIFEST_TARGETS=()
  MANIFEST_IMAGES=()
  MANIFEST_DESCS=()
  MANIFEST_DIRS=()
  local line t img d dir
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    t="${line%%|*}"
    rest="${line#*|}"
    img="${rest%%|*}"
    rest2="${rest#*|}"
    d="${rest2%%|*}"
    dir="${rest2#*|}"
    MANIFEST_TARGETS+=("$t")
    MANIFEST_IMAGES+=("$img")
    MANIFEST_DESCS+=("$d")
    MANIFEST_DIRS+=("$dir")
  done < <(proveo_manifest_entries | sort -t'|' -k1,1)
}

proveo_manifest_image() {
  local want="$1" i
  for i in "${!MANIFEST_TARGETS[@]}"; do
    if [[ "${MANIFEST_TARGETS[$i]}" == "$want" ]]; then
      printf '%s\n' "${MANIFEST_IMAGES[$i]}"
      return 0
    fi
  done
  return 1
}

proveo_manifest_description() {
  local want="$1" i
  for i in "${!MANIFEST_TARGETS[@]}"; do
    if [[ "${MANIFEST_TARGETS[$i]}" == "$want" ]]; then
      printf '%s\n' "${MANIFEST_DESCS[$i]}"
      return 0
    fi
  done
  return 1
}

proveo_manifest_dir() {
  local want="$1" i
  for i in "${!MANIFEST_TARGETS[@]}"; do
    if [[ "${MANIFEST_TARGETS[$i]}" == "$want" ]]; then
      printf '%s\n' "${MANIFEST_DIRS[$i]}"
      return 0
    fi
  done
  return 1
}
