#!/usr/bin/env bash
# tools/u-d16/regenerate-closure.sh — rebuild the l8-flash closure manifest.
#
# The manifest is what makes U-D16's oracle sensitive to `git revert` of any of
# the 30 commits. Ancestry alone is not: a revert ADDS a commit, so
# `git merge-base --is-ancestor e549ba91 HEAD` still answers yes while the
# branch's content has been undone. The manifest pins the content.
#
# It has three parts, all generated from git and never hand-edited:
#
#   closure-blobs.tsv   <blob sha>\t<path>  — for every path the 30 commits
#                       leave PRESENT and that `main` has not touched since
#                       e549ba91. Exact blob identity.
#   closure-absent.txt  one path per line — every path the 30 commits DELETE.
#                       They must still be absent.
#   lines/<slug>.txt    for each path `main` HAS touched since e549ba91: the
#                       lines the 30 commits added that are still present in
#                       HEAD at generation time. Blank lines and duplicates are
#                       dropped (they discriminate nothing). Indexed by
#                       closure-lines.tsv.
#
# Usage: bash tools/u-d16/regenerate-closure.sh
# Re-run it after any commit that legitimately edits a path in the manifest,
# and say in the commit message which row moved and why.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
OUT="$ROOT/tools/u-d16"

# The two ends of the reconciliation, pinned. BASE is ad8a9119's first parent —
# the point `l8-flash` forked from main; HEAD_SHA is the branch head. Between
# them: `git rev-list --count` = 30, the manifest's "30 commits".
BASE="88c7c755"
HEAD_SHA="e549ba911e8d8c9ff1c19b4fa9b0b6df45244f7f"

n="$(git rev-list --count "$BASE..$HEAD_SHA")"
if [ "$n" != "30" ]; then
  echo "regenerate-closure: $BASE..$HEAD_SHA is $n commits, not 30" >&2
  exit 1
fi

# Paths main changed AFTER the reconciliation landed. Their blobs cannot be
# pinned; their l8-flash-added LINES can.
git diff --name-only "$HEAD_SHA" HEAD | sort -u > "$OUT/.evolved"

: > "$OUT/closure-blobs.tsv"
: > "$OUT/closure-absent.txt"
: > "$OUT/closure-lines.tsv"
rm -f "$OUT"/lines/*.txt

git diff --name-status "$BASE" "$HEAD_SHA" | while IFS=$'\t' read -r status path rest; do
  case "$status" in
    D)
      grep -qxF "$path" "$OUT/.evolved" && continue
      printf '%s\n' "$path" >> "$OUT/closure-absent.txt"
      ;;
    A|M)
      if grep -qxF "$path" "$OUT/.evolved"; then
        slug="$(printf '%s' "$path" | tr '/' '_')"
        git diff "$BASE" "$HEAD_SHA" -- "$path" \
          | grep '^+[^+]' | sed 's/^+//' \
          | grep -v '^[[:space:]]*$' | sort -u > "$OUT/.cand"
        : > "$OUT/lines/$slug.txt"
        while IFS= read -r line; do
          # Only lines that survive to HEAD today. A line the 30 commits added
          # and a LATER main commit legitimately rewrote is not evidence of the
          # reconciliation any more, and pinning it would make the oracle red
          # for the wrong reason.
          if grep -qxF -- "$line" "$path" 2>/dev/null; then
            printf '%s\n' "$line" >> "$OUT/lines/$slug.txt"
          fi
        done < "$OUT/.cand"
        printf '%s\t%s\n' "$path" "lines/$slug.txt" >> "$OUT/closure-lines.tsv"
      else
        blob="$(git rev-parse "$HEAD_SHA:$path")"
        printf '%s\t%s\n' "$blob" "$path" >> "$OUT/closure-blobs.tsv"
      fi
      ;;
    *)
      echo "regenerate-closure: unhandled status '$status' for '$path'" >&2
      exit 1
      ;;
  esac
done

rm -f "$OUT/.evolved" "$OUT/.cand"
sort -o "$OUT/closure-blobs.tsv" "$OUT/closure-blobs.tsv"
sort -o "$OUT/closure-absent.txt" "$OUT/closure-absent.txt"
sort -o "$OUT/closure-lines.tsv" "$OUT/closure-lines.tsv"

printf 'closure: %s blob rows, %s absent rows, %s line files\n' \
  "$(wc -l < "$OUT/closure-blobs.tsv")" \
  "$(wc -l < "$OUT/closure-absent.txt")" \
  "$(wc -l < "$OUT/closure-lines.tsv")"
