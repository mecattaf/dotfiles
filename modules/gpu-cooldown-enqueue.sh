#!/usr/bin/env bash
# Local adapter from the coordinator sensor tripwire to its fixed Tally receiver.
# Failure stays loud and non-zero so the poller remains armed and retries.
set -euo pipefail

temp_c="${1:?usage: gpu-cooldown-enqueue <temp_c> <sensor_kind> <threshold_c>}"
sensor_kind="${2:?}"
threshold="${3:?}"

receiver="${TALLY_COOLDOWN_RECEIVER:-/etc/profiles/per-user/tom/bin/tally-gpu-cooldown}"
cooldown_min="${COOLDOWN_MINUTES:-30}"

[[ "$temp_c" =~ ^[0-9]+$ ]]
[[ "$threshold" =~ ^[0-9]+$ ]]
[[ "$sensor_kind" =~ ^[A-Za-z0-9:_-]+$ ]]
[[ "$cooldown_min" =~ ^[1-9][0-9]*$ ]]
[[ "$receiver" =~ ^/[A-Za-z0-9/_+.,@=-]+$ ]]
secs=$(( cooldown_min * 60 ))

if "$receiver" "$temp_c" "$sensor_kind" "$threshold" "$secs"; then
  echo "gpu-cooldown-enqueue: queued ${cooldown_min}-min coordinator-gpu hold (trigger ${temp_c}C on ${sensor_kind})"
  exit 0
fi

echo "gpu-cooldown-enqueue: FALLBACK no-op — local enqueue failed. GPU is HOT: ${temp_c}C on ${sensor_kind} >= ${threshold}C. NO coordinator-gpu lease was taken." >&2
exit 1
