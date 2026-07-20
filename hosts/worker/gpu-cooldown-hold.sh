#!/usr/bin/env bash
# Direct-exec leaf run by tally while holding the worker-gpu pool.
set -euo pipefail

temp_c="${1:?usage: gpu-cooldown-hold <temp_c> <sensor_kind> <threshold_c> <seconds>}"
sensor_kind="${2:?}"
threshold="${3:?}"
secs="${4:?}"

[[ "$secs" =~ ^[1-9][0-9]*$ ]] || {
  echo "gpu-cooldown-hold: seconds must be a positive integer" >&2
  exit 2
}

logger -t tally -p daemon.warning \
  "gpu-cooldown fired: trigger=${temp_c}C threshold=${threshold}C sensor=${sensor_kind} host=worker"
exec sleep "$secs"
