#!/usr/bin/env bash
# gpu-cooldown-enqueue — LAYER 2 (the tally seam adapter).
#
# Enqueues a fixed-duration worker-GPU "cooldown" job through the tally daemon on
# the conductor. The job takes the single pls `worker-gpu` lease (PLS_CAPACITY=1)
# and holds it for the whole rest window, so every other GPU consumer on the
# worker sees the pool as busy (mock-busy) and backs off — the GPU gets to cool.
#
# The tally daemon lives on the conductor (coordinator); the worker reaches it the
# same way it reaches sessions — over ssh (tally CLI is a thin socket client;
# CLI-SURFACE.md §2.1 / §3.2). We run `ssh <conductor> tally enqueue …`.
#
# WITNESS — the trigger temperature travels WITH the job two ways:
#   1. --dedup-key: recorded verbatim in tally's witness ledger row
#      (~/.local/share/tally/witness.jsonl `dedup_key`). Timestamped so each
#      genuine trip is its own row and is never dedup-skipped.
#   2. a `logger -t tally` line emitted by the leaf on the conductor → lands in
#      journald under tag `tally`, i.e. in `tally query log`.
#
# Fallback: if the enqueue cannot be placed (conductor unreachable, tally down),
# this is a LOUD no-op — it logs at error level and returns non-zero so LAYER 1
# stays armed and retries. It never fakes success and never holds a local lease.
#
# Args: <trigger_temp_c> <sensor_kind> <threshold_c>
set -euo pipefail

temp_c="${1:?usage: gpu-cooldown-enqueue <temp_c> <sensor_kind> <threshold_c>}"
sensor_kind="${2:?}"
threshold="${3:?}"

conductor="${TALLY_CONDUCTOR_HOST:-coordinator}"
cooldown_min="${COOLDOWN_MINUTES:-30}"
secs=$(( cooldown_min * 60 ))
stamp="$(date -u +%Y%m%dT%H%M%SZ)"

# dedup-key: witness carrier. No spaces (colon is fine); timestamped => unique.
dedup="gpu-cooldown-worker-${sensor_kind}-${temp_c}C-${stamp}"

# Leaf command run on the conductor UNDER the pls worker-gpu lease: announce the
# trigger to journald, then hold the lease `secs`. `exec` so the systemd unit's
# main PID is the sleep. Natural completion after the rest window exits 0.
leaf="logger -t tally -p daemon.warning gpu-cooldown fired: trigger=${temp_c}C sensor=${sensor_kind} host=worker; exec sleep ${secs}"

# --source calendar: a systemd TIMER is an autonomous/queued producer, so it earns
# a DURABLE TaskChampion row (task_uuid) + a witness.jsonl row — which is what
# carries `dedup_key` (the trigger temp) into tally's durable ledger, and lets the
# job survive a daemon crash. (`orchestrator` is reserved for live-orchestrator-
# spawned rowless units, whose witness would NOT land in witness.jsonl — see
# tally src/contracts/task.ts `admitsDurableRow`, "timers are calendar".)
#
# ssh space-joins its argv and the REMOTE login shell (fish) re-parses the join,
# so the remote command must be ONE self-quoted string. Single-quotes protect the
# leaf's `;` for fish; the inner `sh -c` then runs it as one script.
remote="tally enqueue --kind shell --source calendar --pool worker-gpu --priority high --dedup-key '${dedup}' --evidence exit:0 --json -- sh -c '${leaf}'"

# -n: redirect ssh stdin from /dev/null so it never swallows the caller's stdin.
if ssh -n -o BatchMode=yes -o ConnectTimeout=10 "$conductor" "$remote"; then
  echo "gpu-cooldown-enqueue: enqueued ${cooldown_min}-min worker-gpu cooldown (trigger ${temp_c}C on ${sensor_kind}) via ${conductor}"
  exit 0
fi

echo "gpu-cooldown-enqueue: FALLBACK no-op — could not place cooldown on ${conductor} (ssh/tally failed). GPU is HOT: ${temp_c}C on ${sensor_kind} >= ${threshold}C. NO worker-gpu lease taken; other consumers still see the GPU as free." >&2
exit 1
