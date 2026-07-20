#!/usr/bin/env bash
# gpu-cooldown-enqueue — LAYER 2 (worker sensor → central Tally seam).
#
# The worker owns only the hardware observation. It invokes one fixed receiver on
# coordinator, where the sole Tally daemon enqueues a local 30-minute sleep against
# the logical worker-gpu pool. Interrupt priority puts the hold first in line, but
# worker-gpu has hardPreempt=false, so an active LLM task is never killed.
#
# Fallback is deliberately loud and non-zero: LAYER 1 stays armed and retries on
# its next poll. It never pretends a lease exists when coordinator is unreachable.
set -euo pipefail

temp_c="${1:?usage: gpu-cooldown-enqueue <temp_c> <sensor_kind> <threshold_c>}"
sensor_kind="${2:?}"
threshold="${3:?}"

conductor="${TALLY_CONDUCTOR_HOST:-coordinator}"
identity="${TALLY_IDENTITY_FILE:?TALLY_IDENTITY_FILE is required}"
known_hosts="${TALLY_KNOWN_HOSTS:-/etc/ssh/ssh_known_hosts}"
receiver="${TALLY_COOLDOWN_RECEIVER:-/etc/profiles/per-user/tom/bin/tally-gpu-cooldown}"
cooldown_min="${COOLDOWN_MINUTES:-30}"

[[ "$temp_c" =~ ^[0-9]+$ ]]
[[ "$threshold" =~ ^[0-9]+$ ]]
[[ "$sensor_kind" =~ ^[A-Za-z0-9:_-]+$ ]]
[[ "$cooldown_min" =~ ^[1-9][0-9]*$ ]]
[[ "$receiver" =~ ^/[A-Za-z0-9/_+.,@=-]+$ ]]
secs=$(( cooldown_min * 60 ))

if ssh -F /dev/null -n \
  -o BatchMode=yes \
  -o PasswordAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  -o IdentitiesOnly=yes \
  -o IdentityAgent=none \
  -o ForwardAgent=no \
  -o ClearAllForwardings=yes \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$known_hosts" \
  -o ConnectTimeout=10 \
  -o ConnectionAttempts=1 \
  -i "$identity" \
  "tom@$conductor" "$receiver" "$temp_c" "$sensor_kind" "$threshold" "$secs"; then
  echo "gpu-cooldown-enqueue: queued ${cooldown_min}-min central worker-gpu hold (trigger ${temp_c}C on ${sensor_kind})"
  exit 0
fi

echo "gpu-cooldown-enqueue: FALLBACK no-op — coordinator enqueue failed. GPU is HOT: ${temp_c}C on ${sensor_kind} >= ${threshold}C. NO worker-gpu lease was taken." >&2
exit 1
