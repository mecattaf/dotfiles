set -euo pipefail

prompt="${1:?usage: local-ai-monthly-judge <prompt.md> <evidence.md> <context.md> <hf-metadata.md> <provider> <model> <llama-swap-url> <output.md> <state-dir>}"
evidence="${2:?}"
context="${3:?}"
hf_metadata="${4:?}"
provider="${5:?}"
model="${6:?}"
llama_swap_url="${7:?}"
output="${8:?}"
state_dir="${9:?}"

umask 077
mkdir -p "$state_dir" "$(dirname "$output")"
temporary="$output.tmp"

PI_CODING_AGENT_DIR="$state_dir" \
PI_TELEMETRY=0 \
LLAMA_SWAP_URL="$llama_swap_url" \
"$LOCAL_AI_PI" \
  --extension "$LOCAL_AI_PI_PROVIDER_EXTENSION" \
  --no-extensions \
  --no-skills \
  --no-prompt-templates \
  --no-context-files \
  --no-session \
  --no-approve \
  --no-tools \
  --print \
  --mode text \
  --provider "$provider" \
  --model "$model" \
  "@$prompt" \
  "@$evidence" \
  "@$context" \
  "@$hf_metadata" \
  'Write only the proposed pull-request commentary now.' \
  > "$temporary"

bytes="$(wc -c < "$temporary")"
if ((bytes < 40 || bytes > 50000)); then
  printf 'local-ai-monthly: Pi commentary has invalid size: %s bytes\n' "$bytes" >&2
  exit 1
fi
if grep -q '<!-- local-ai-monthly-state' "$temporary"; then
  printf 'local-ai-monthly: Pi commentary attempted to write workflow state\n' >&2
  exit 1
fi
mv "$temporary" "$output"
