#!/usr/bin/env bash
# assemble.sh <paper-dir> <uuid> <sha256> <title> <out-md> <page>:<source>...
# source is one of: vlm8b vlm32b mech
set -euo pipefail
. "$(dirname "$0")/env.sh"
dir="$1"; uuid="$2"; sha="$3"; title="$4"; out="$5"; shift 5
mkdir -p "$(dirname "$out")"
tmp="$out.tmp.$$"
{
  printf -- '---\nuuid: %s\ntitle: "%s"\nsha256: %s\npipeline: tally-flow-e2e-2026-08-04\n---\n' "$uuid" "$title" "$sha"
  for spec in "$@"; do
    page="${spec%%:*}"; src="${spec#*:}"
    case "$src" in
      vlm8b)  f="$dir/vlm/$(printf '%03d' "$page").md" ;;
      vlm32b) f="$dir/refine/$(printf '%03d' "$page").md" ;;
      mech)   f="$dir/mech/$(printf '%03d' "$page")/poppler.txt" ;;
      *) echo "unknown source $src" >&2; exit 7 ;;
    esac
    [ -s "$f" ] || { echo "missing page artifact $f" >&2; exit 8; }
    printf '\n<!-- page:%03d source:%s -->\n\n' "$page" "$src"
    "$CORE/cat" "$f"
    printf '\n'
  done
} > "$tmp"
mv "$tmp" "$out"
