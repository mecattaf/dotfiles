#!/usr/bin/env bash
# gpu-cooldown-enqueue — LAYER 2 (the tally seam adapter).
#
# Enqueues a fixed-duration worker-GPU cooldown job through the worker-local
# tally daemon. The direct-exec holder takes the single `worker-gpu` lease for
# the whole rest window, so cooperating local GPU consumers back off while the
# GPU cools.
#
# WITNESS — the trigger temperature travels WITH the job two ways:
#   1. --dedup-key: recorded verbatim in tally's witness ledger row
#      (~/.local/share/tally/witness.jsonl `dedup_key`). Timestamped so each
#      genuine trip is its own row and is never dedup-skipped.
#   2. a `logger -t tally` line emitted by the holder on the worker.
#
# Fallback: if the local enqueue cannot be placed, this is a LOUD no-op — it
# returns non-zero so LAYER 1 stays armed and retries. It never fakes success.
#
# Args: <trigger_temp_c> <sensor_kind> <threshold_c>
set -euo pipefail

temp_c="${1:?usage: gpu-cooldown-enqueue <temp_c> <sensor_kind> <threshold_c>}"
sensor_kind="${2:?}"
threshold="${3:?}"

socket="${TALLY_SOCKET:-/run/user/$(id -u)/tally/tally.sock}"
holder="${COOLDOWN_HOLDER:?COOLDOWN_HOLDER must point at the direct-exec holder}"
cooldown_min="${COOLDOWN_MINUTES:-30}"
secs=$(( cooldown_min * 60 ))
stamp="$(date -u +%Y%m%dT%H%M%SZ)"

# dedup-key: witness carrier. No spaces (colon is fine); timestamped => unique.
dedup="gpu-cooldown-worker-${sensor_kind}-${temp_c}C-${stamp}"

# --source calendar: a systemd TIMER is an autonomous/queued producer, so it earns
# a DURABLE TaskChampion row (task_uuid) + a witness.jsonl row — which is what
# carries `dedup_key` (the trigger temp) into tally's durable ledger. The holder
# is passed as direct argv; no shell string is rendered by this adapter.
if tally --socket "$socket" enqueue \
  --source calendar \
  --pool worker-gpu \
  --priority high \
  --dedup-key "$dedup" \
  --evidence exit:0 \
  -- "$holder" "$temp_c" "$sensor_kind" "$threshold" "$secs"; then
  echo "gpu-cooldown-enqueue: enqueued ${cooldown_min}-min local worker-gpu cooldown (trigger ${temp_c}C on ${sensor_kind})"
  exit 0
fi

echo "gpu-cooldown-enqueue: FALLBACK no-op — local tally enqueue failed. GPU is HOT: ${temp_c}C on ${sensor_kind} >= ${threshold}C. NO worker-gpu lease taken; other consumers still see the GPU as free." >&2
exit 1
