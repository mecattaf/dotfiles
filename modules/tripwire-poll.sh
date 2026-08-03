#!/usr/bin/env bash
# One oneshot poll of one myTripwire instance: sample, decide, maybe fire, emit.
#
# Sensor contract — print exactly ONE line to stdout:
#
#     <value> [<kind>] [<threshold>]
#
#   value      integer sample (required)
#   kind       label naming the sample source (default: the tripwire name)
#   threshold  per-sample threshold override (default: TRIPWIRE_THRESHOLD), for
#              sensors that pick between sources which do not share a trip point
#
# State (armed / first_over / refractory_until) lives under $STATE_DIRECTORY so
# hysteresis and the sustain window survive each oneshot.
#
# Alert identity is the label set, never a sample value and never the current
# time: EPISODE_ID is "<kind>-<first_over>", the episode start. A retry after a
# failed onFire reuses that exact key, so an idempotent receiver collapses the
# duplicate; a genuinely new episode gets a new key and a real new action.
set -euo pipefail

name="${TRIPWIRE_NAME:?TRIPWIRE_NAME must be set}"
sensor="${TRIPWIRE_SENSOR:?TRIPWIRE_SENSOR must point at the sensor script}"
on_fire="${TRIPWIRE_ONFIRE:?TRIPWIRE_ONFIRE must point at the onFire script}"
default_threshold="${TRIPWIRE_THRESHOLD:?}"
rearm="${TRIPWIRE_REARM:?}"
sustain="${TRIPWIRE_SUSTAIN:-0}"
refractory="${TRIPWIRE_REFRACTORY:-0}"
comparison="${TRIPWIRE_COMPARISON:-ge}"
value_field="${TRIPWIRE_VALUE_FIELD:-VALUE}"

# systemd hands StateDirectory as a colon-separated list; we declare exactly one.
state_dir="${STATE_DIRECTORY%%:*}"
state="$state_dir/state"

if ! sample="$("$sensor")"; then
  echo "tripwire[$name]: sensor FAILED; refusing to run blind" >&2
  exit 1
fi

read -r -a fields <<<"$(printf '%s\n' "$sample" | head -n 1)"
value="${fields[0]:-}"
kind="${fields[1]:-$name}"
threshold="${fields[2]:-$default_threshold}"

if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
  echo "tripwire[$name]: sensor emitted a non-integer value '${value}'" >&2
  exit 1
fi
if ! [[ "$kind" =~ ^[A-Za-z0-9:_.-]+$ ]]; then
  echo "tripwire[$name]: sensor emitted an unusable kind '${kind}'" >&2
  exit 1
fi
if ! [[ "$threshold" =~ ^-?[0-9]+$ ]]; then
  echo "tripwire[$name]: sensor emitted a non-integer threshold '${threshold}'" >&2
  exit 1
fi

armed=1
first_over=0
refractory_until=0
if [ -f "$state" ]; then
  # shellcheck disable=SC1090
  . "$state"
fi
[ -n "${armed:-}" ] || armed=1
[ -n "${first_over:-}" ] || first_over=0
[ -n "${refractory_until:-}" ] || refractory_until=0

# "ge" trips when the sample rises to the threshold and re-arms once it falls
# back below rearm; "le" is the mirror, for sensors where low is the bad
# direction (free bytes, battery charge).
over=0
if [ "$comparison" = "le" ]; then
  if [ "$value" -le "$threshold" ]; then over=1; fi
  if [ "$value" -gt "$rearm" ]; then armed=1; fi
else
  if [ "$value" -ge "$threshold" ]; then over=1; fi
  if [ "$value" -lt "$rearm" ]; then armed=1; fi
fi

now="$(date +%s)"
if [ "$over" -eq 1 ]; then
  [ "$first_over" -ne 0 ] || first_over="$now"
else
  first_over=0
fi
held_for=0
if [ "$first_over" -ne 0 ]; then
  held_for=$(( now - first_over ))
fi

# Captured before firing, which clears first_over to close the episode.
episode_start="$first_over"
episode_id="${kind}-${episode_start}"

decision="nominal"
if [ "$over" -eq 1 ]; then
  if [ "$now" -lt "$refractory_until" ]; then
    decision="suppressed"
  elif [ "$armed" -eq 1 ] && [ "$held_for" -ge "$sustain" ]; then
    decision="fire"
  else
    decision="accumulating"
  fi
fi

if [ "$decision" = "fire" ]; then
  export TRIPWIRE_NAME="$name"
  export TRIPWIRE_VALUE="$value"
  export TRIPWIRE_SENSOR_KIND="$kind"
  export TRIPWIRE_THRESHOLD="$threshold"
  export TRIPWIRE_HELD_FOR="$held_for"
  export TRIPWIRE_EPISODE_ID="$episode_id"
  export TRIPWIRE_EPISODE_START="$episode_start"
  if "$on_fire" "$value" "$kind" "$threshold" "$episode_id"; then
    decision="fired"
    armed=0
    refractory_until=$(( now + refractory ))
    first_over=0
  else
    # Stay armed on the same episode so the next poll retries under the same
    # key rather than inventing a second alert identity.
    decision="fire-failed"
  fi
fi

priority=6
case "$decision" in
  accumulating) priority=5 ;;
  fired) priority=4 ;;
  fire-failed) priority=3 ;;
esac

emit=(
  "MESSAGE=tripwire[${name}] ${decision}: ${kind}=${value} vs ${threshold} held=${held_for}s armed=${armed}"
  "PRIORITY=${priority}"
  "SYSLOG_IDENTIFIER=tripwire"
  "TRIPWIRE=${name}"
  "SENSOR_KIND=${kind}"
  "${value_field}=${value}"
  "THRESHOLD=${threshold}"
  "HELD_FOR=${held_for}"
  "SUSTAIN=${sustain}"
  "ARMED=${armed}"
  "DECISION=${decision}"
)
if [ "$episode_start" -ne 0 ]; then
  emit+=( "EPISODE_ID=${episode_id}" "EPISODE_START=${episode_start}" )
fi
if ! printf '%s\n' "${emit[@]}" | logger --journald; then
  printf '%s\n' "${emit[@]}" >&2
fi

{
  echo "armed=${armed}"
  echo "first_over=${first_over}"
  echo "refractory_until=${refractory_until}"
} > "$state"

# A tripwire that saw the condition and could not act on it is itself a failure
# worth surfacing — the state file is already durable at this point.
[ "$decision" != "fire-failed" ]
