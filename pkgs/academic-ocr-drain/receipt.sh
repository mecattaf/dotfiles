#!/usr/bin/env bash
# receipt.sh <paper-dir> <uuid> <out-receipt-json> <embeddings-backend|-> <page>:<source>...
# Fixed receipt: identity, per-page provenance, artifact digests, and whether
# the embed and index stages ran. `-` as the backend means none was named
# (ACADEMIC_OCR_EMBEDDINGS_URL unset) and both stages were skipped; the
# receipt records that outright so a later pass can rebuild them from
# chunks.json instead of mistaking the gap for a finished paper.
set -euo pipefail
. "$(dirname "$0")/env.sh"
dir="$1"; uuid="$2"; out="$3"; backend="$4"; shift 4
mkdir -p "$(dirname "$out")"
if [ "$backend" = "-" ]; then
  embeddings_json='{"status":"skipped","backend":null,"reason":"ACADEMIC_OCR_EMBEDDINGS_URL unset: no fleet server offers /v1/embeddings; embed and index stages skipped"}'
else
  embeddings_json=$("$JQ" -nc --arg b "$backend" '{status: "embedded", backend: $b}')
fi
pages_json=$(for spec in "$@"; do
  printf '{"page":%d,"source":"%s"}\n' "${spec%%:*}" "${spec#*:}"
done | "$JQ" -s '.')
digest() { [ -f "$1" ] && "$CORE/sha256sum" "$1" | cut -d' ' -f1 || echo absent; }
"$JQ" -n \
  --arg uuid "$uuid" \
  --arg finished "$("$CORE/date" -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson pages "$pages_json" \
  --arg paperMd "$(digest "$dir/canonical/paper.md")" \
  --arg chunks "$(digest "$dir/canonical/chunks.json")" \
  --arg embeddings "$(digest "$dir/canonical/embeddings.json")" \
  --arg index "$(digest "$dir/canonical/index.jsonl")" \
  --argjson embeddingStage "$embeddings_json" \
  '{schemaVersion: 1, paperId: $uuid, finishedAt: $finished, pages: $pages,
    embeddingStage: $embeddingStage,
    artifacts: {paperMd: $paperMd, chunks: $chunks, embeddings: $embeddings, index: $index}}' \
  > "$out.tmp"
mv "$out.tmp" "$out"
