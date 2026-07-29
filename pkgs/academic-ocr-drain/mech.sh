#!/usr/bin/env bash
# mech.sh <pdf> <page> <out-dir>
# Two independent mechanical text extractions. Fails closed (exit 3) when both
# engines find no meaningful text layer (scanned page).
set -euo pipefail
. "$(dirname "$0")/env.sh"
pdf="$1"; page="$2"; outdir="$3"
mkdir -p "$outdir"
"$POPPLER/pdftotext" -f "$page" -l "$page" "$pdf" "$outdir/poppler.txt"
"$MUPDF/mutool" draw -q -F text -o "$outdir/mupdf.txt" "$pdf" "$page"
pw=$("$CORE/cat" "$outdir/poppler.txt" | "$AWK" '{n+=NF} END {print n+0}')
mw=$("$CORE/cat" "$outdir/mupdf.txt" | "$AWK" '{n+=NF} END {print n+0}')
"$JQ" -n --argjson pw "$pw" --argjson mw "$mw" \
  '{popplerWords: $pw, mupdfWords: $mw}' > "$outdir/mech.json"
if [ "$pw" -lt 20 ] && [ "$mw" -lt 20 ]; then
  echo "no usable text layer (poppler=$pw mupdf=$mw words)" >&2
  exit 3
fi
