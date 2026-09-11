set -euo pipefail

prompt="${1:?usage: local-ai-monthly-judge <prompt.md> <evidence.md> <context.md> <hf-metadata.md> <provider> <model> <output.md> <state-dir>}"
evidence="${2:?}"
context="${3:?}"
hf_metadata="${4:?}"
provider="${5:?}"
model="${6:?}"
output="${7:?}"
state_dir="${8:?}"

umask 077
mkdir -p "$state_dir" "$(dirname "$output")"
temporary="$output.tmp"

# Pi resolves the provider and model through its declared models.json, which
# names the Halogen Flash server; the judge selects them by id only. The run
# gets a private agent directory, so that declaration is copied in first.
models_json="${PI_CODING_AGENT_DIR:-${HOME:?}/.pi/agent}/models.json"
if ! jq -e --arg provider "$provider" --arg model "$model" \
  '.providers[$provider].models | any(.id == $model)' "$models_json" >/dev/null 2>&1; then
  printf 'local-ai-monthly: %s does not declare provider %s with model %s\n' \
    "$models_json" "$provider" "$model" >&2
  exit 1
fi
cp -f "$models_json" "$state_dir/models.json"

PI_CODING_AGENT_DIR="$state_dir" \
PI_TELEMETRY=0 \
"$LOCAL_AI_PI" \
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
