#!/usr/bin/env bash
# index.sh <chunks-json> <embeddings-json> <out-index-jsonl>
# Disposable retrieval index: one JSONL row per chunk with text + vector.
# Rebuildable from chunks.json + embeddings.json alone.
set -euo pipefail
. "$(dirname "$0")/env.sh"
chunks="$1"; emb="$2"; out="$3"
mkdir -p "$(dirname "$out")"
nc=$("$JQ" 'length' "$chunks")
nv=$("$JQ" '.vectors | length' "$emb")
[ "$nc" -eq "$nv" ] || { echo "chunk/vector count mismatch $nc != $nv" >&2; exit 11; }
"$JQ" -c --slurpfile e "$emb" '
  ($e[0].vectors | map({(.chunkId|tostring): .embedding}) | add) as $vecs
  | .[] | . + {embedding: $vecs[.chunkId|tostring]}' "$chunks" > "$out.tmp"
mv "$out.tmp" "$out"
