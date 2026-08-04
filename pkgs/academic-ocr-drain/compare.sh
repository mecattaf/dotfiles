#!/usr/bin/env bash
# compare.sh <ref-txt> <cand-txt> <out-verdict-json> <min-agreement-permille> [min-words]
# Dice coefficient over normalized word multisets. Exit 3 when below threshold —
# the failed verdict is the flow's routing signal to the specialist lane.
# min-words (default 0) additionally fails any side under the floor; the
# mech-first shortcut (dotfiles#147) uses it to route sparse-text-layer pages
# (figures, covers) to the VLM lane even when both engines agree.
set -euo pipefail
. "$(dirname "$0")/env.sh"
mech="$1"; vlm="$2"; out="$3"; min="$4"; minwords="${5:-0}"
mkdir -p "$(dirname "$out")"
norm() { "$CORE/tr" '[:upper:]' '[:lower:]' < "$1" | "$CORE/tr" -cs '[:alnum:]' '\n' | "$AWK" 'length($0)>=2' | "$CORE/sort"; }
norm "$mech" > "$out.a.$$"
norm "$vlm"  > "$out.b.$$"
na=$("$CORE/cat" "$out.a.$$" | "$AWK" 'END{print NR+0}')
nb=$("$CORE/cat" "$out.b.$$" | "$AWK" 'END{print NR+0}')
common=$("$CORE/comm" -12 "$out.a.$$" "$out.b.$$" | "$AWK" 'END{print NR+0}')
rm -f "$out.a.$$" "$out.b.$$"
total=$((na + nb))
if [ "$total" -eq 0 ]; then agree=0; else agree=$((2000 * common / total)); fi
# Truncation guard (June rule, dotfiles#127): when the mechanical reference is
# voucher-eligible (>=200 words), a candidate under 60% of its length is a
# truncated transcription even if word overlap clears the agreement gate.
truncated=false
if [ "$na" -ge 200 ] && [ $((nb * 1000)) -lt $((600 * na)) ]; then
  truncated=true
fi
"$JQ" -n --argjson a "$agree" --argjson na "$na" --argjson nb "$nb" --argjson c "$common" --argjson t "$truncated" \
  '{agreementPermille: $a, refWords: $na, candWords: $nb, commonWords: $c, truncationSuspected: $t}' > "$out"
if [ "$na" -lt "$minwords" ] || [ "$nb" -lt "$minwords" ]; then
  echo "word floor: ref=$na cand=$nb below min-words $minwords" >&2
  exit 3
fi
if [ "$truncated" = true ]; then
  echo "candidate $nb words < 60% of reference $na words: truncation suspected" >&2
  exit 3
fi
if [ "$agree" -lt "$min" ]; then
  echo "agreement $agree < $min permille" >&2
  exit 3
fi
