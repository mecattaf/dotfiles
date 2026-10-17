#!/usr/bin/env bash
# hy-memory-serve: the hand-run llama-server for the hy-memory-30b-a3b-q8-0
# catalogue row (DECISIONS.md 2026-10-17). Loopback only, one request in
# flight, 32k context, the GGUF card's tested flag set, reasoning off.
#
# It refuses to download anything: the model comes from
# /var/lib/local-models via `sudo local-models-borrow --yes`, never from `-hf`.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: hy-memory-serve [--help] [extra llama-server flags]

environment:
  MODEL     GGUF path (default /var/lib/local-models/hy-memory-30b-a3b-q8-0/Hy-Memory-30B-A3B-Q8_0.gguf)
  TEMPLATE  chat template (default: chat_template.jinja beside MODEL)
  PORT      loopback port (default 8081)
  MEMORY_SWEEP_LLAMA_SERVER  the llama-server binary (set by the package)

Refuses: -hf / --hf-repo / --hf-file (bytes enter through library-fetch and
local-models-borrow only), a missing model file, and a start when MemAvailable
is below the model size plus 12 GiB.
EOF
}

refuse() {
  echo "hy-memory-serve: REFUSING: $*" >&2
  exit 2
}

for arg in "$@"; do
  case "$arg" in
    -h | --help)
      usage
      exit 0
      ;;
    -hf | -hf=* | --hf-repo | --hf-repo=* | -hff | --hf-file | --hf-file=* | -hfd | --hf-repo-draft | --hf-repo-draft=*)
      refuse "runtime downloads are not allowed ($arg); borrow the row with: sudo local-models-borrow --yes"
      ;;
  esac
done

MODEL="${MODEL:-/var/lib/local-models/hy-memory-30b-a3b-q8-0/Hy-Memory-30B-A3B-Q8_0.gguf}"
TEMPLATE="${TEMPLATE:-$(dirname "$MODEL")/chat_template.jinja}"
PORT="${PORT:-8081}"
SERVER="${MEMORY_SWEEP_LLAMA_SERVER:?MEMORY_SWEEP_LLAMA_SERVER is not set}"

[ -x "$SERVER" ] || refuse "llama-server not executable at $SERVER"
[ -r "$MODEL" ] || refuse "model missing at $MODEL; run: sudo local-models-borrow --dry-run, then sudo local-models-borrow --yes"
[ -r "$TEMPLATE" ] || refuse "chat template missing at $TEMPLATE (it is part of the same catalogue row)"

# Memory preflight: the GGUF is mmapped into unified memory, plus a 32k f16
# KV cache (about 3.2 GiB) and headroom. Never stop Halogen, Gufo or Herdr to
# make room; pick Q6_K or wait instead (design section 10).
model_bytes="$(stat -c %s "$MODEL")"
mem_available_kib="$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo 2>/dev/null || echo 0)"
mem_available=$((mem_available_kib * 1024))
headroom=$((12 * 1024 * 1024 * 1024))
if [ "${HY_MEMORY_SKIP_MEMCHECK:-0}" != "1" ] && [ "$mem_available" -lt $((model_bytes + headroom)) ]; then
  refuse "MemAvailable is $mem_available bytes, below model ($model_bytes) + 12 GiB headroom; do not stop Halogen or Gufo for this, run it when the box is quieter or switch the row to Q6_K"
fi

exec "$SERVER" \
  --model "$MODEL" \
  --alias hy-memory \
  --host 127.0.0.1 \
  --port "$PORT" \
  --n-gpu-layers all \
  --flash-attn on \
  --ctx-size 32768 \
  --parallel 1 \
  --batch-size 512 \
  --ubatch-size 256 \
  --cache-type-k f16 \
  --cache-type-v f16 \
  --jinja \
  --chat-template-file "$TEMPLATE" \
  --chat-template-kwargs '{"reasoning_effort":"no_think"}' \
  --metrics \
  "$@"
