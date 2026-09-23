#!/usr/bin/env bash
# ax-agent: the command an ax Task runs in the fleet's task image.
#
#   ax-agent halogen-smoke   one chat completion against Halogen with curl
#   ax-agent pi              pi against Halogen, result validated against a
#                            JSON Schema (the probe's adapter-pi.sh, e1)
#   ax-agent fetch URL       GET URL; exits with curl's code (egress checks)
#   ax-agent exit N          exit with code N
#
# Every mode writes its result to $AX_RESULT_PATH (default .ax/result.json
# under the workspace), which P1's runner serves to the controller once the
# command exits. No mode reads or needs a secret: Halogen has no auth, and no
# Claude credential exists in this image (DESIGN.md section 11).
set -uo pipefail

mode="${1:-}"
[ $# -gt 0 ] && shift
out="${AX_RESULT_PATH:-${AX_CONWIP_RESULT_PATH:-.ax/result.json}}"
mkdir -p "$(dirname "$out")"
halogen="${HALOGEN_URL:-http://10.42.0.5:8731}"
model="${AX_AGENT_MODEL:-${AX_CONWIP_MODEL:-halogen-qwen3.8-flash-next}}"
share="@share@"

case "$mode" in
halogen-smoke)
  body=$(jq -nc --arg m "$model" \
    '{model:$m, max_tokens:32, messages:[{role:"user", content:"Reply with the single word: ok"}]}')
  curl -sS --max-time 300 -H 'content-type: application/json' \
    -d "$body" "$halogen/v1/chat/completions" >"$out.raw"
  rc=$?
  content=$(jq -r '.choices[0].message.content // empty' "$out.raw" 2>/dev/null)
  jq -n --arg mode "$mode" --arg model "$model" --arg url "$halogen" --argjson rc "$rc" \
    --arg content "$content" \
    '{mode:$mode, model:$model, halogen:$url, curl_rc:$rc, ok:($rc == 0 and ($content | length) > 0), content:$content}' >"$out"
  echo "ax-agent halogen-smoke: curl rc=$rc content_bytes=${#content}"
  [ "$rc" -eq 0 ] && [ -n "$content" ]
  ;;

pi)
  # pi reads its providers from ~/.pi/agent/models.json (pi README). HOME is
  # /workspace/.home, which survives a suspend.
  mkdir -p "$HOME/.pi/agent"
  sed "s#@HALOGEN_URL@#${halogen}#" "$share/pi-models.json" >"$HOME/.pi/agent/models.json"
  prompt="${AX_CONWIP_PROMPT:-What is 6 times 7? Answer with the number.}"
  default_schema='{"type":"object","required":["answer"],"properties":{"answer":{"type":"integer"}}}'
  schema="${AX_CONWIP_SCHEMA_JSON:-$default_schema}"
  sys="Return only one JSON object, no prose and no code fence, that validates against this JSON Schema: ${schema}"
  t0=$(date +%s.%N)
  raw=$(pi -p --provider halogen --model "$model" --thinking "${AX_CONWIP_EFFORT:-low}" \
    --no-session --no-tools --no-context-files --no-skills --no-extensions --no-prompt-templates --offline \
    --append-system-prompt "$sys" "$prompt" 2>"$out.stderr")
  rc=$?
  t1=$(date +%s.%N)
  printf '%s' "$raw" >"$out.raw"
  verdict=$(printf '%s' "$raw" | python3 "$share/validate.py" "$schema")
  vrc=$?
  jq -n --arg label "${AX_CONWIP_LABEL:-}" --arg model "$model" --arg effort "${AX_CONWIP_EFFORT:-low}" \
    --argjson rc "$rc" --argjson v "$verdict" --arg secs "$(python3 -c "print($t1-$t0)")" --arg cwd "$PWD" \
    '{label:$label, model:$model, effort:$effort, harness:"pi", harness_rc:$rc,
      valid:$v.valid, errors:$v.errors, result:$v.value, seconds:($secs|tonumber), cwd:$cwd}' >"$out"
  echo "ax-agent pi: valid=$(jq .valid "$out") rc=$rc vrc=$vrc"
  [ "$rc" -eq 0 ] && [ "$vrc" -eq 0 ]
  ;;

fetch)
  url="${1:?usage: ax-agent fetch URL}"
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "$url")
  rc=$?
  jq -n --arg url "$url" --argjson rc "$rc" --arg code "$code" '{mode:"fetch", url:$url, curl_rc:$rc, http_code:$code}' >"$out"
  echo "ax-agent fetch: $url rc=$rc http=$code"
  exit "$rc"
  ;;

exit)
  n="${1:-0}"
  jq -n --argjson n "$n" '{mode:"exit", code:$n}' >"$out"
  exit "$n"
  ;;

*)
  echo "usage: ax-agent halogen-smoke | pi | fetch URL | exit N" >&2
  exit 64
  ;;
esac
