#!/usr/bin/env bash
# chunk.sh <paper-md> <uuid> <out-chunks-json>
# Deterministic page-grounded chunking: one chunk per page marker.
set -euo pipefail
. "$(dirname "$0")/env.sh"
md="$1"; uuid="$2"; out="$3"
mkdir -p "$(dirname "$out")"
"$AWK" -v RS='' 'BEGIN{page=0}
  /^<!-- page:[0-9]+ / { match($0, /page:([0-9]+) source:([a-z0-9]+)/, m); page=m[1]; src=m[2]; next }
  page>0 { gsub(/\t/, " "); gsub(/\n/, " "); printf "%d\t%s\t%s\n", page, src, $0; }' "$md" \
| "$JQ" -R --arg uuid "$uuid" -s '
    [ split("\n")[] | select(length>0) | split("\t")
      | {paperId: $uuid, page: (.[0]|tonumber), source: .[1], text: (.[2:] | join(" "))} ]
    | to_entries | map(.value + {chunkId: (.key)})' > "$out.tmp"
mv "$out.tmp" "$out"
n=$("$JQ" 'length' "$out")
[ "$n" -gt 0 ] || { echo "zero chunks" >&2; exit 9; }
