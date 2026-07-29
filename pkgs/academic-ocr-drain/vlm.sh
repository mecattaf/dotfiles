#!/usr/bin/env bash
# vlm.sh <png> <model> <out-md>
# One bounded VLM transcription through llama-swap. June-proven prompt, temp 0.
# All large payloads travel via files, never argv (128 KiB per-arg kernel cap).
set -euo pipefail
. "$(dirname "$0")/env.sh"
png="$1"; model="$2"; out="$3"
mkdir -p "$(dirname "$out")"
work=$("$CORE/mktemp" -d)
trap 'rm -rf "$work"' EXIT
prompt="Transcribe this scanned academic page to clean GitHub-flavored Markdown. Preserve heading levels, paragraphs, footnotes, and tables (as markdown tables). Use \$...\$ / \$\$...\$\$ for math. Do not add commentary. If part is illegible write [illegible]."
"$CORE/base64" -w0 "$png" > "$work/b64"
"$JQ" -n --arg model "$model" --arg prompt "$prompt" --rawfile b64 "$work/b64" \
  '{model: $model, temperature: 0, max_tokens: 6000,
    messages: [{role: "user", content: [
      {type: "text", text: $prompt},
      {type: "image_url", image_url: {url: ("data:image/png;base64," + $b64)}}]}]}' \
  > "$work/body.json"
"$CURL" -fsS --max-time 1500 -H 'Content-Type: application/json' \
  -d @"$work/body.json" "$LLAMA_SWAP/v1/chat/completions" > "$work/resp.json"
finish=$("$JQ" -r '.choices[0].finish_reason // empty' "$work/resp.json")
if [ "$finish" = "length" ]; then
  echo "VLM output truncated at max_tokens (finish_reason=length)" >&2
  exit 7
fi
"$JQ" -r '.choices[0].message.content' "$work/resp.json" > "$work/raw.md"
[ -s "$work/raw.md" ] && [ "$(head -c 4 "$work/raw.md")" != "null" ] \
  || { echo "empty VLM response" >&2; exit 6; }
# strip accidental code fences (June behavior)
"$AWK" 'NR==1 && ($0=="```markdown" || $0=="```") {next} {print}' "$work/raw.md" \
  | "$AWK" 'BEGIN{n=0} {lines[++n]=$0} END{if (n>0 && lines[n]=="```") n--; for(i=1;i<=n;i++) print lines[i]}' \
  > "$out.tmp"
[ -s "$out.tmp" ] || { echo "empty after fence strip" >&2; exit 6; }
mv "$out.tmp" "$out"
