#!/usr/bin/env bash
# embed.sh <chunks-json> <model> <out-embeddings-json>
set -euo pipefail
. "$(dirname "$0")/env.sh"
chunks="$1"; model="$2"; out="$3"
mkdir -p "$(dirname "$out")"
n=$("$JQ" 'length' "$chunks")
: > "$out.tmp"
for i in $(seq 0 $((n - 1))); do
  text=$("$JQ" -r ".[$i].text" "$chunks" | "$CORE/head" -c 8000)
  body=$("$JQ" -n --arg model "$model" --arg input "$text" '{model: $model, input: $input}')
  vec=$("$CURL" -fsS --max-time 600 -H 'Content-Type: application/json' \
    -d "$body" "$LLAMA_SWAP/v1/embeddings" | "$JQ" -c '.data[0].embedding')
  dim=$(printf '%s' "$vec" | "$JQ" 'length')
  [ "$dim" -ge 1024 ] || { echo "bad embedding dim $dim for chunk $i" >&2; exit 10; }
  "$JQ" -nc --argjson i "$i" --argjson v "$vec" '{chunkId: $i, embedding: $v}' >> "$out.tmp"
done
"$JQ" -s --arg model "$model" '{model: $model, vectors: .}' "$out.tmp" > "$out.final"
rm "$out.tmp"
mv "$out.final" "$out"
