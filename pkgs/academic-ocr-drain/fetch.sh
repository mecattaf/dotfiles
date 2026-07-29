#!/usr/bin/env bash
# fetch.sh <url> <sha256> <out-blob-path>
set -euo pipefail
. "$(dirname "$0")/env.sh"
url="$1"; want="$2"; out="$3"
mkdir -p "$(dirname "$out")"
if [ -f "$out" ]; then
  got=$("$CORE/sha256sum" "$out" | cut -d' ' -f1)
  [ "$got" = "$want" ] && exit 0
  rm -f "$out"
fi
tmp="$out.tmp.$$"
"$CURL" -fsSL --max-time 300 -o "$tmp" "$url"
got=$("$CORE/sha256sum" "$tmp" | cut -d' ' -f1)
if [ "$got" != "$want" ]; then
  echo "sha256 mismatch: got $got want $want" >&2
  rm -f "$tmp"
  exit 4
fi
head -c 5 "$tmp" | grep -q '%PDF-' || { echo "not a PDF" >&2; rm -f "$tmp"; exit 5; }
mv "$tmp" "$out"
