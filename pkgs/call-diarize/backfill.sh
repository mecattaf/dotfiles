#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: call-diarize-backfill [recordings-root]" >&2
  exit 1
}

events_directory() {
  if [[ -n "${TALLY_EVENTS_DIR:-}" ]]; then
    printf '%s\n' "${TALLY_EVENTS_DIR}"
  elif [[ -n "${XDG_STATE_HOME:-}" ]]; then
    printf '%s\n' "${XDG_STATE_HOME}/tally/events"
  else
    : "${HOME:?HOME is required when XDG_STATE_HOME and TALLY_EVENTS_DIR are unset}"
    printf '%s\n' "${HOME}/.local/state/tally/events"
  fi
}

warn_if_daemon_unavailable() {
  local socket
  if [[ -n "${TALLY_SOCKET:-}" ]]; then
    socket="${TALLY_SOCKET}"
  elif [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    socket="${XDG_RUNTIME_DIR}/tally/tally.sock"
  else
    echo "warning: tally daemon availability is unknown; event is queued for a later drain" >&2
    return
  fi

  if [[ ! -S "$socket" ]]; then
    echo "warning: tally daemon is unavailable; event is queued for a later drain" >&2
  fi
}

enqueue_directory() {
  local requested_dir="$1"
  local call_dir directory_name dedup_key event_hash
  local events_dir event_path temporary

  if [[ ! -d "$requested_dir" ]]; then
    echo "call-diarize-backfill: not a call directory: $requested_dir" >&2
    return 1
  fi
  if ! call_dir="$(realpath "$requested_dir")"; then
    echo "call-diarize-backfill: cannot resolve call directory: $requested_dir" >&2
    return 1
  fi

  directory_name="${call_dir##*/}"
  dedup_key="call-diarize:${directory_name}"
  events_dir="$(events_directory)"
  if ! mkdir -p -- "$events_dir"; then
    echo "call-diarize-backfill: cannot create tally events directory: $events_dir" >&2
    return 1
  fi

  if ! event_hash="$(printf '%s' "$dedup_key" | sha256sum)"; then
    echo "call-diarize-backfill: cannot derive event identity for: $call_dir" >&2
    return 1
  fi
  event_hash="${event_hash%% *}"
  event_path="$events_dir/call-diarize-${event_hash:0:32}.json"
  if ! temporary="$(mktemp "$events_dir/.call-diarize.XXXXXXXXXX")"; then
    echo "call-diarize-backfill: cannot create an atomic event in: $events_dir" >&2
    return 1
  fi

  # For /home/tom/Recordings/calls/2026-08-09-demo this writes exactly:
  # {"argv":["call-diarize","/home/tom/Recordings/calls/2026-08-09-demo"],"adapter":"shell","pool":["coordinator-gpu"],"priority":"low","source":"events-dir","dedupKey":"call-diarize:2026-08-09-demo","submission":{"mode":"full"},"evidence":["exit:0"],"runtimeMaxSec":21600,"noEnqueue":true}
  if ! jq -cn \
    --arg call_dir "$call_dir" \
    --arg dedup_key "$dedup_key" \
    '{
      argv: ["call-diarize", $call_dir],
      adapter: "shell",
      pool: ["coordinator-gpu"],
      priority: "low",
      source: "events-dir",
      dedupKey: $dedup_key,
      submission: {mode: "full"},
      evidence: ["exit:0"],
      runtimeMaxSec: 21600,
      noEnqueue: true
    }' >"$temporary"; then
    rm -f -- "$temporary"
    echo "call-diarize-backfill: cannot render event for: $call_dir" >&2
    return 1
  fi

  if ! mv -fT -- "$temporary" "$event_path"; then
    rm -f -- "$temporary"
    echo "call-diarize-backfill: cannot publish event: $event_path" >&2
    return 1
  fi

  printf 'queued diarization: %s -> %s\n' "$call_dir" "$event_path"
}

if [[ "${1:-}" == "--enqueue" ]]; then
  [[ $# -eq 2 ]] || usage
  enqueue_directory "$2"
  warn_if_daemon_unavailable
  exit 0
fi

[[ $# -le 1 ]] || usage
if [[ $# -eq 1 ]]; then
  recordings_root="$1"
elif [[ -n "${CALL_RECORDINGS_ROOT:-}" ]]; then
  recordings_root="${CALL_RECORDINGS_ROOT}"
else
  : "${HOME:?HOME is required when CALL_RECORDINGS_ROOT is unset}"
  recordings_root="${HOME}/Recordings/calls"
fi

if [[ ! -d "$recordings_root" ]]; then
  echo "call-diarize-backfill: no recordings directory: $recordings_root" >&2
  exit 0
fi

queued=0
failed=0
while IFS= read -r -d '' call_dir; do
  if [[ -e "$call_dir/transcript.md" ]]; then
    continue
  fi
  if enqueue_directory "$call_dir"; then
    ((queued += 1))
  else
    ((failed += 1))
  fi
done < <(find "$recordings_root" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

printf 'call-diarize-backfill: queued %d recording(s)' "$queued"
if ((failed > 0)); then
  printf '; failed %d' "$failed"
fi
printf '\n'

if ((queued > 0)); then
  warn_if_daemon_unavailable
fi
((failed == 0))
