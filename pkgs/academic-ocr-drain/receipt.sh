#!/usr/bin/env bash
# receipt.sh <paper-dir> <uuid> <out-receipt-json> <page>:<source>...
# Fixed receipt: identity, per-page provenance, artifact digests.
set -euo pipefail
. "$(dirname "$0")/env.sh"
dir="$1"; uuid="$2"; out="$3"; shift 3
mkdir -p "$(dirname "$out")"
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
  '{schemaVersion: 1, paperId: $uuid, finishedAt: $finished, pages: $pages,
    artifacts: {paperMd: $paperMd, chunks: $chunks, embeddings: $embeddings, index: $index}}' \
  > "$out.tmp"
mv "$out.tmp" "$out"
