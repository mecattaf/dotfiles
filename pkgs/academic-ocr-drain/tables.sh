#!/usr/bin/env bash
# tables.sh <mech-txt> <out-verdict-json> [min-numeric-run]
# Table-evidence gate for the mech-first shortcut (Tom's ruling, 2026-08-06:
# tables route to the VLM lane). Exit 3 when the page shows table evidence —
# a failed verdict is the flow's routing signal, same protocol as compare.sh.
#
# Why this exists: the text layer linearizes a table column-major. Every value
# survives, but the row/column association does not, and the mech-vs-mech
# agreement gate structurally cannot catch it — poppler and mupdf linearize
# identically and agree perfectly on the wrong reading. Only the VLM sees the
# page as a picture and emits a GFM table.
#
# Two signals, both cheap and both computed off the mechanical text:
#   captionLines   a "Table N" caption anchored at line start
#   maxNumericRun  consecutive bare-numeric lines — the direct fingerprint of
#                  column-major linearization, which emits one cell per line
# Calibrated 2026-08-06 against 2,181 already-drained pages that cleared the
# mech word floor and went to the VLM anyway, scored on whether the VLM output
# actually contains a GFM table (240 do):
#   caption alone            76.2% recall  2.0% false positive  10.2% rerouted
#   caption OR run>=4        85.0% recall  3.6% false positive  12.6% rerouted
#   caption OR run>=6        82.1% recall  3.1% false positive  11.8% rerouted
# run>=4 is the ship: the numeric-run half buys 9 points of recall for 1.6 of
# false positives. A false positive costs one VLM page; a false negative costs
# a silently scrambled table in the canonical corpus, so the trade is not
# symmetric — recall is the number to buy.
#
# Forward cost on the real population (every page that has resolved
# source:mech to date, 2026-08-06): 463 of 2,662 pages, 17.4%. Caption alone
# would be 415, 15.6% — so the ~12% quoted when the ruling was made was already
# low for the caption half, and the numeric-run half adds 1.8 points on top.
#
# Numeric density measured *per line* was tried and dropped: it
# fired on author-affiliation numbering and stats-in-prose, adding 6 pages of
# which every sampled one was a false positive.
set -euo pipefail
. "$(dirname "$0")/env.sh"
src="$1"; out="$2"; minrun="${3:-4}"
mkdir -p "$(dirname "$out")"

stats=$("$AWK" '
  # pdftotext emits form feeds at column and page breaks. Those are hard line
  # breaks for this purpose (they end a numeric column), so make them record
  # separators rather than ordinary characters inside a record.
  BEGIN { RS = "[\n\v\f]" }
  /^[ \t]*(TABLE|Table|Tab\.)[ \t]*[0-9IVXivx]+([^A-Za-z0-9]|$)/ { caps++ }
  {
    t = $0
    gsub(/[ \t\r]/, "", t)
    if (t == "") next          # blank lines neither extend nor break a run
    s = t
    gsub(/[0-9.,()+%*$-]/, "", s)
    if (s == "" && t ~ /[0-9]/) { run++; if (run > best) best = run }
    else run = 0
  }
  END { printf "%d %d\n", caps + 0, best + 0 }
' "$src")
caps="${stats%% *}"; run="${stats##* }"

"$JQ" -n --argjson caps "$caps" --argjson run "$run" --argjson min "$minrun" \
  '{captionLines: $caps, maxNumericRun: $run, minNumericRun: $min,
    tableEvidence: ($caps > 0 or $run >= $min)}' > "$out"

if [ "$caps" -gt 0 ]; then
  echo "table caption on $caps line(s): mech text linearizes tables; routing to the VLM lane" >&2
  exit 3
fi
if [ "$run" -ge "$minrun" ]; then
  echo "$run consecutive bare-numeric lines >= $minrun: column-major linearization; routing to the VLM lane" >&2
  exit 3
fi
