#!/usr/bin/env bash
# Enumerate harness targets/images from defs/*/harness.manifest (single registration).
# Canonical copy for maintainer mise / lib/runners.sh (not shipped on the consumer CDN).
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
# Top-level keys are detected by leading indentation (not an allowlist): any unindented
# key other than name/description/images ends the images: block, so new manifest fields
# (provider, dind, …) cannot be mistaken for image targets.
proveo_manifest_entries() {
  local defs f name desc in_images key val defdir raw line trimmed
  defs="$(proveo_defs_root)" || return 1
  shopt -s nullglob
  for f in "$defs"/*/harness.manifest; do
    [[ -f "$f" ]] || continue
    defdir="$(dirname "$f")"
    name=""
    desc=""
    in_images=0
    while IFS= read -r raw || [[ -n "$raw" ]]; do
      line="${raw%%#*}"
      trimmed="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [[ -n "$trimmed" ]] || continue

      # Unindented line ⇒ top-level YAML key (ends or starts a block).
      if [[ "$line" == "$trimmed" && "$trimmed" == *:* ]]; then
        key="${trimmed%%:*}"
        case "$key" in
          name)
            name="$(printf '%s' "${trimmed#name:}" | sed -e 's/^[[:space:]]*//')"
            in_images=0
            ;;
          description)
            desc="$(printf '%s' "${trimmed#description:}" | sed -e 's/^[[:space:]]*//')"
            in_images=0
            ;;
          images)
            in_images=1
            ;;
          *)
            in_images=0
            ;;
        esac
        continue
      fi

      if (( in_images )) && [[ "$trimmed" == *:* ]]; then
        key="$(printf '%s' "${trimmed%%:*}" | sed -e 's/[[:space:]]*$//')"
        val="$(printf '%s' "${trimmed#*:}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [[ -n "$key" && -n "$val" ]] || continue
        printf '%s|%s|%s|%s\n' "$key" "$val" "$desc" "$defdir"
      fi
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
  local line t img d dir rest rest2
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
