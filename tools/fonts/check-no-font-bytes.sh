#!/usr/bin/env bash
# check-no-font-bytes.sh: the font bytes guard for this repository.
#
# What it is: a read only check that no tracked file is a font binary. It
# lists tracked paths with `git ls-files -z` and fails if any path carries a
# font extension (ttf otf woff woff2 ttc pfb) or if the file's first four
# bytes are a font magic header (OTTO, true, ttcf, wOFF, wOF2, or 00 01 00 00,
# the TrueType sfnt version). It then prints the sha256 pins of the NAS
# tarballs named by `requireFile` in pkgs/*.nix: those pins are the only
# lawful reference to font bytes in git.
#
# What it replaced and when: added 2026-10-22 on branch
# dryrun/shell-consolidation-2026-10-22. Before it the rule lived only in
# .gitignore (lines under "Font binaries never enter this repo", 2026-09-17)
# and in docs/fonts/README.md "Standing rules". .gitignore does not stop
# `git add -f` and does not cover a font saved under another extension; this
# script does.
#
# Deliberately absent: it never reads a font, never touches fontconfig, never
# fetches anything and never writes. It checks the working tree copy of each
# tracked path, not the index blob (a staged file deleted from the working
# tree is skipped). Symlinks are skipped by content (the target is not a
# tracked blob) but still checked by extension.
#
# Usage: tools/fonts/check-no-font-bytes.sh [repo-dir]
# Exit: 0 no font bytes tracked, 1 font bytes found, 2 usage or git error.
set -euo pipefail

repo="${1:-}"
if [[ -z "$repo" ]]; then
  repo="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "check-no-font-bytes: not inside a git repository" >&2
    exit 2
  }
fi
cd "$repo" || exit 2
git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "check-no-font-bytes: $repo is not a git repository" >&2
  exit 2
}

# Four byte magic headers, as lower case hex.
#   4f54544f OTTO (CFF OpenType)   74727565 true (Apple TrueType)
#   74746366 ttcf (collection)     774f4646 wOFF   774f4632 wOF2
#   00010000 TrueType sfnt version 1.0
is_font_magic() {
  case "$1" in
    4f54544f | 74727565 | 74746366 | 774f4646 | 774f4632 | 00010000) return 0 ;;
    *) return 1 ;;
  esac
}

scanned=0
hits=0
while IFS= read -r -d '' path; do
  scanned=$((scanned + 1))
  lower="${path,,}"
  case "$lower" in
    *.ttf | *.otf | *.woff | *.woff2 | *.ttc | *.pfb)
      echo "FONT (extension): $path"
      hits=$((hits + 1))
      continue
      ;;
  esac
  [[ -f "$path" && ! -L "$path" ]] || continue
  magic="$(head -c 4 -- "$path" | od -An -tx1 | tr -d ' \n')"
  if is_font_magic "$magic"; then
    echo "FONT (magic $magic): $path"
    hits=$((hits + 1))
  fi
done < <(git ls-files -z)

echo "tracked files scanned: $scanned"
echo "font files found: $hits"

echo "lawful references (requireFile pins in pkgs/*.nix):"
shopt -s nullglob
pins=0
for nix in pkgs/*.nix; do
  while IFS=$'\t' read -r name sha; do
    printf '  %s  %s  (%s)\n' "$sha" "$name" "$nix"
    pins=$((pins + 1))
  done < <(awk '
    /requireFile[ \t]*\{/ { inblk = 1; name = ""; sha = "" }
    inblk && match($0, /name[ \t]*=[ \t]*"[^"]+"/) {
      s = substr($0, RSTART, RLENGTH); sub(/^[^"]*"/, "", s); sub(/"$/, "", s); name = s
    }
    inblk && match($0, /sha256[ \t]*=[ \t]*"[0-9a-f]{64}"/) {
      s = substr($0, RSTART, RLENGTH); sub(/^[^"]*"/, "", s); sub(/"$/, "", s); sha = s
    }
    inblk && name != "" && sha != "" { print name "\t" sha; inblk = 0 }
  ' "$nix")
done
echo "pins found: $pins"

if ((hits > 0)); then
  echo "FAIL: font bytes are tracked. Remove them with git rm --cached and keep them on the NAS." >&2
  exit 1
fi
echo "OK: no font bytes tracked."
