#!/usr/bin/env bash
# raster.sh <pdf> <page> <dpi> <out-png>
set -euo pipefail
. "$(dirname "$0")/env.sh"
pdf="$1"; page="$2"; dpi="$3"; out="$4"
mkdir -p "$(dirname "$out")"
tmp="${out%.png}.tmp"
"$POPPLER/pdftoppm" -png -r "$dpi" -f "$page" -l "$page" -singlefile "$pdf" "$tmp"
mv "$tmp.png" "$out"
[ -s "$out" ]
