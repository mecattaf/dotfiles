#!/usr/bin/env bash
# myTripwire sensor: coordinator GPU die temperature.
#
# Prints "<temp_c> <sensor_kind> <threshold_c>". amdgpu's junction reading is
# preferred; k10temp Tctl is the fallback when the discrete label is absent.
# Each source carries its own threshold because the two do not trip at the same
# temperature, and the sensor is the only thing that knows which one it read.
set -euo pipefail

junction_c="${JUNCTION_THRESHOLD_C:-90}"
tctl_c="${TCTL_THRESHOLD_C:-85}"
hwmon_root="${HWMON_ROOT:-/sys/class/hwmon}"

find_label() {
  local want_name="$1" want_label="$2" h nm lf
  for h in "$hwmon_root"/hwmon*; do
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

sensor_input=""
sensor_kind=""
threshold=""
if sensor_input="$(find_label amdgpu junction)"; then
  sensor_kind="amdgpu:junction"
  threshold="$junction_c"
elif sensor_input="$(find_label k10temp Tctl)"; then
  sensor_kind="k10temp:Tctl"
  threshold="$tctl_c"
else
  echo "gpu sensor: FATAL: no amdgpu 'junction' nor k10temp 'Tctl' hwmon node found" >&2
  exit 1
fi

if [ ! -r "$sensor_input" ]; then
  echo "gpu sensor: FATAL: sensor input $sensor_input unreadable" >&2
  exit 1
fi

milli="$(cat "$sensor_input")"
temp_c=$(( milli / 1000 ))
if [ -n "${FAKE_TEMP_C:-}" ]; then
  temp_c="$FAKE_TEMP_C"
  # stderr, never stdout: stdout is the sensor's one-line contract.
  echo "gpu sensor: NOTE FAKE_TEMP_C override in effect (${temp_c}C)" >&2
fi

printf '%s %s %s\n' "$temp_c" "$sensor_kind" "$threshold"
