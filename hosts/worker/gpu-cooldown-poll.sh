#!/usr/bin/env bash
# gpu-cooldown-poll — LAYER 1 (sensor + trigger logic).
#
# Polled every ~30s by the gpu-cooldown-tripwire.timer. Reads the amdgpu junction
# temperature (falling back to k10temp Tctl when junction is absent — the case on
# this worker, whose amdgpu hwmon only exposes `edge`), and on a SUSTAINED over-
# threshold reading fires LAYER 2 (the enqueue adapter). Never touches tally
# itself; the adapter owns that seam.
#
# Hysteresis / suppression (all persisted in $STATE):
#   * armed      — a fresh trip is only allowed after the temp has dropped below
#                  REARM_THRESHOLD_C since the last trip (disarm-on-fire).
#   * first_over — epoch of the first consecutive over-threshold poll; the trip
#                  needs (now - first_over) >= SUSTAIN_SECONDS (~2-3 polls).
#   * cooldown_until — while now < this, a cooldown is active/pending: suppressed.
#
# Test hook: set FAKE_TEMP_C to override the reading (real sensor still selected)
# so the trip path can be exercised without a hot GPU.
set -euo pipefail

state_dir="${STATE_DIRECTORY:-/var/lib/gpu-cooldown}"
state="$state_dir/state"
junction_c="${JUNCTION_THRESHOLD_C:-90}"
tctl_c="${TCTL_THRESHOLD_C:-85}"
rearm_c="${REARM_THRESHOLD_C:-75}"
sustain_s="${SUSTAIN_SECONDS:-60}"
cooldown_min="${COOLDOWN_MINUTES:-30}"
adapter="${COOLDOWN_ADAPTER:?COOLDOWN_ADAPTER must point at the enqueue adapter}"

# --- sensor discovery: match by hwmon NAME + temp LABEL at runtime (never a
#     hardcoded hwmonN). Prefer amdgpu junction; fall back to k10temp Tctl. ---
find_label() { # $1=hwmon name  $2=temp label  -> prints matching *_input path
  local want_name="$1" want_label="$2" h nm lf
  for h in /sys/class/hwmon/hwmon*; do
    [ -r "$h/name" ] || continue
    nm="$(cat "$h/name")"
    [ "$nm" = "$want_name" ] || continue
    for lf in "$h"/temp*_label; do
      [ -e "$lf" ] || continue
      if [ "$(cat "$lf")" = "$want_label" ]; then
        printf '%s\n' "${lf%_label}_input"
        return 0
      fi
    done
  done
  return 1
}

sensor_input="" ; sensor_kind="" ; threshold=""
if sensor_input="$(find_label amdgpu junction)"; then
  sensor_kind="amdgpu:junction" ; threshold="$junction_c"
elif sensor_input="$(find_label k10temp Tctl)"; then
  sensor_kind="k10temp:Tctl" ; threshold="$tctl_c"
else
  echo "gpu-cooldown: FATAL: no amdgpu 'junction' nor k10temp 'Tctl' hwmon node found; sensor layout changed — refusing to run blind" >&2
  exit 1
fi
[ -r "$sensor_input" ] || { echo "gpu-cooldown: FATAL: sensor input $sensor_input unreadable" >&2; exit 1; }

milli="$(cat "$sensor_input")"
temp_c=$(( milli / 1000 ))
if [ -n "${FAKE_TEMP_C:-}" ]; then
  temp_c="$FAKE_TEMP_C"
  echo "gpu-cooldown: NOTE FAKE_TEMP_C override in effect (${temp_c}C)"
fi
now="$(date +%s)"

# --- load persisted state ---
armed=1 ; first_over=0 ; cooldown_until=0
if [ -f "$state" ]; then
  # shellcheck disable=SC1090
  . "$state"
fi
[ -n "${armed:-}" ] || armed=1
[ -n "${first_over:-}" ] || first_over=0
[ -n "${cooldown_until:-}" ] || cooldown_until=0

# --- hysteresis: only re-arm once we cool below the re-arm threshold ---
if [ "$temp_c" -lt "$rearm_c" ]; then
  armed=1
fi

# --- sustained over-threshold tracking ---
over=0
[ "$temp_c" -ge "$threshold" ] && over=1
if [ "$over" -eq 1 ]; then
  [ "$first_over" -ne 0 ] || first_over="$now"
else
  first_over=0
fi
held_for=0
[ "$first_over" -ne 0 ] && held_for=$(( now - first_over ))

decision="nominal"
if [ "$now" -lt "$cooldown_until" ]; then
  decision="suppressed(cooldown active/pending)"
elif [ "$over" -eq 1 ] && [ "$armed" -eq 1 ] && [ "$first_over" -ne 0 ] && [ "$held_for" -ge "$sustain_s" ]; then
  decision="trigger"
elif [ "$over" -eq 1 ]; then
  decision="accumulating(${held_for}s/${sustain_s}s armed=${armed})"
fi

echo "gpu-cooldown: sensor=${sensor_kind} temp=${temp_c}C threshold=${threshold}C armed=${armed} over=${over} decision=${decision}"

if [ "$decision" = "trigger" ]; then
  if "$adapter" "$temp_c" "$sensor_kind" "$threshold"; then
    armed=0
    cooldown_until=$(( now + cooldown_min * 60 + 60 ))
    first_over=0
    echo "gpu-cooldown: TRIGGERED at ${temp_c}C (${sensor_kind}); cooldown enqueued — disarmed until temp<${rearm_c}C AND cooldown window elapses (until epoch ${cooldown_until})"
  else
    echo "gpu-cooldown: adapter FAILED to enqueue (GPU HOT at ${temp_c}C); staying armed, retry next poll" >&2
  fi
fi

# --- persist ---
{
  echo "armed=${armed}"
  echo "first_over=${first_over}"
  echo "cooldown_until=${cooldown_until}"
} > "$state"
