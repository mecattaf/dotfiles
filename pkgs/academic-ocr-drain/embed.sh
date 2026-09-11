#!/usr/bin/env bash
# embed.sh <chunks-json> <model> <endpoint> <out-embeddings-json>
# No fleet server offers /v1/embeddings. The endpoint is an operator-run
# llama-server serving the loanable embedding artifact, carried from
# ACADEMIC_OCR_EMBEDDINGS_URL through the flow args; the flow never dispatches
# this tool without one, and it refuses to run without one.
set -euo pipefail
. "$(dirname "$0")/env.sh"
chunks="$1"; model="$2"; endpoint="$3"; out="$4"
case "$endpoint" in
  http://*|https://*) ;;
  *) echo "embed.sh: no embeddings backend: set ACADEMIC_OCR_EMBEDDINGS_URL to an http(s) base URL (got '$endpoint')" >&2; exit 12 ;;
esac
mkdir -p "$(dirname "$out")"
n=$("$JQ" 'length' "$chunks")
: > "$out.tmp"
for i in $(seq 0 $((n - 1))); do
  text=$("$JQ" -r ".[$i].text" "$chunks" | "$CORE/head" -c 8000)
  body=$("$JQ" -n --arg model "$model" --arg input "$text" '{model: $model, input: $input}')
  vec=$("$CURL" -fsS --max-time 600 -H 'Content-Type: application/json' \
    -d "$body" "$endpoint/v1/embeddings" | "$JQ" -c '.data[0].embedding')
  dim=$(printf '%s' "$vec" | "$JQ" 'length')
  [ "$dim" -ge 1024 ] || { echo "bad embedding dim $dim for chunk $i" >&2; exit 10; }
  "$JQ" -nc --argjson i "$i" --argjson v "$vec" '{chunkId: $i, embedding: $v}' >> "$out.tmp"
done
"$JQ" -s --arg model "$model" --arg endpoint "$endpoint" '{model: $model, endpoint: $endpoint, vectors: .}' "$out.tmp" > "$out.final"
rm "$out.tmp"
mv "$out.final" "$out"
