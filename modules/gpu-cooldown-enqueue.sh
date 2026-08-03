#!/usr/bin/env bash
# onFire adapter for the coordinator GPU tripwire: the ONE place the tripwire
# touches tally.
#
# Observation upstream of this file is plain systemd; if tally changes shape
# only this script changes, and if tally were gone the tripwire would keep
# sampling and logging. The enqueued job is a plain sleep holding the
# coordinator-gpu lease at interrupt priority — the pool is non-preemptive, so
# an in-flight GPU job is slowed, never killed.
#
# The dedup key is the EPISODE identity (`<sensor_kind>-<episode start>`),
# never the sample temperature and never the current time. That is what makes
# tally's idempotence real: a retry after a failed enqueue presents the same
# key and collapses into the existing hold, while the next distinct heat
# episode presents a new key and takes a genuinely new one. The previous key
# embedded temp_c and a fresh timestamp, so every attempt looked new and the
# only thing preventing duplicate holds was the poller's state file.
#
# Failure stays loud and non-zero so the poller remains armed and retries.
set -euo pipefail

temp_c="${1:?usage: gpu-cooldown-enqueue <temp_c> <sensor_kind> <threshold_c> <episode_id>}"
sensor_kind="${2:?}"
threshold="${3:?}"
episode_id="${4:?}"

tally_bin="${TALLY_BIN:-/etc/profiles/per-user/tom/bin/tally}"
sleep_bin="${SLEEP_BIN:-/run/current-system/sw/bin/sleep}"
pool="${COOLDOWN_POOL:-coordinator-gpu}"
priority="${COOLDOWN_PRIORITY:-interrupt}"
cooldown_min="${COOLDOWN_MINUTES:-30}"

[[ "$temp_c" =~ ^[0-9]+$ ]]
[[ "$threshold" =~ ^[0-9]+$ ]]
[[ "$sensor_kind" =~ ^[A-Za-z0-9:_.-]+$ ]]
[[ "$episode_id" =~ ^[A-Za-z0-9:_.-]+$ ]]
[[ "$cooldown_min" =~ ^[1-9][0-9]*$ ]]
[[ "$pool" =~ ^[A-Za-z0-9_-]+$ ]]
[[ "$priority" =~ ^[a-z]+$ ]]
[[ "$tally_bin" =~ ^/[A-Za-z0-9/_+.,@-]+$ ]]
[[ "$sleep_bin" =~ ^/[A-Za-z0-9/_+.,@-]+$ ]]

secs=$(( cooldown_min * 60 ))
socket="${TALLY_SOCKET:-/run/user/$(id -u)/tally/tally.sock}"
dedup="gpu-cooldown-coordinator-${episode_id}"

if "$tally_bin" --socket "$socket" enqueue \
  --source calendar \
  --pool "$pool" \
  --priority "$priority" \
  --dedup-key "$dedup" \
  --no-enqueue \
  --evidence exit:0 \
  -- "$sleep_bin" "$secs"; then
  echo "gpu-cooldown-enqueue: queued ${cooldown_min}-min ${pool} hold (dedup ${dedup}, trigger ${temp_c}C on ${sensor_kind})"
  exit 0
fi

echo "gpu-cooldown-enqueue: FALLBACK no-op — local enqueue failed. GPU is HOT: ${temp_c}C on ${sensor_kind} >= ${threshold}C. NO ${pool} lease was taken." >&2
exit 1
