set -euo pipefail

payload=''
for argument in "$@"; do
  case $argument in
    @*) payload=${argument#@} ;;
  esac
done
[[ -n $payload && -f $payload ]] || {
  printf 'academic-ocr-fake-curl: no @payload argument\n' >&2
  exit 2
}

if jq -e 'has("messages")' "$payload" >/dev/null; then
  jq -cn '{
    choices: [{
      message: {
        content: "# Fixture paper\n\nThis generated academic page tests deterministic visual transcription through the bounded llama-swap HTTP adapter. It preserves headings, paragraphs, citations, tables, and mathematical notation without adding commentary.\n\n## Findings\n\nThe controlled fixture contains enough substantive language for the OCR fail-closed gate and the downstream chunking test."
      }
    }]
  }'
elif jq -e 'has("input")' "$payload" >/dev/null; then
  jq -c '
    .input
    | to_entries
    | {data: [ .[] | {index: .key, embedding: [range(0; 4096) | ((. + 1) / 4096)]} ]}
  ' "$payload"
else
  printf 'academic-ocr-fake-curl: unsupported payload\n' >&2
  exit 2
fi
