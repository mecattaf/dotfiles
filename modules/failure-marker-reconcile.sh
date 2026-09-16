#!/usr/bin/env bash
# Remove only failure markers whose corresponding unit manager now reports
# healthy state. Journald remains the durable incident history; the interactive
# marker directory is reserved for failures that are still actionable.
set -euo pipefail

marker_dir="${FAILURE_MARKER_DIR:?FAILURE_MARKER_DIR must be set}"
read -r -a user_manager_uids <<<"${USER_MANAGER_UIDS:-}"

[ -d "$marker_dir" ] || exit 0

# Serialize against both marker writers. Without this lock, a recovery poll
# could unlink a marker between its truncate and final chmod.
exec 9>"$marker_dir/.failure-marker-reconcile.lock"
flock 9

clear_marker() {
  local marker="$1"
  local reason="$2"
  local name
  name="$(basename -- "$marker")"
  rm -f -- "$marker"
  printf '%s\n' \
    "MESSAGE=recovered failure marker cleared: $name ($reason)" \
    "PRIORITY=5" \
    "SYSLOG_IDENTIFIER=failure-marker-reconcile" \
    "MARKER=$name" \
    "DECISION=recovered-marker-cleared" | logger --journald || true
}

# The user-unit watcher aggregates every watched manager into one marker. Keep
# it whenever a manager cannot be queried or still has a failed unit; clear it
# only after every watched manager answers successfully with an empty failed set.
user_marker="$marker_dir/user-unit-failure"
if [ -f "$user_marker" ] && [ "${#user_manager_uids[@]}" -gt 0 ]; then
  all_user_managers_healthy=1
  for uid in "${user_manager_uids[@]}"; do
    # Use the manager's own socket as the user. --machine=UID@.host starts a
    # transient PAM/login bridge: when the bus is damaged that bridge itself
    # fails and generates another fleet failure marker on every probe.
    if ! failed_units="$(
      runuser -u "$(id -nu "$uid")" -- env \
        XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/systemd/private" \
        systemctl --user --failed --plain --no-legend --no-pager \
        2>/dev/null
    )"; then
      all_user_managers_healthy=0
      break
    fi
    if [ -n "$failed_units" ]; then
      all_user_managers_healthy=0
      break
    fi
  done
  if [ "$all_user_managers_healthy" -eq 1 ]; then
    clear_marker "$user_marker" "all watched user managers are healthy"
  fi
fi

# Blanket system-unit markers have a stable first-line grammar:
#   <unit> failed at <time> — journalctl ...
# Leave event markers (coredumps, cache health, journal digests) untouched, and
# retain any unit that systemd still considers failed.
shopt -s nullglob
for marker in "$marker_dir"/*; do
  [ -f "$marker" ] || continue
  [ "$marker" != "$user_marker" ] || continue
  first_line="$(head -n 1 -- "$marker" 2>/dev/null || true)"
  read -r unit verb _ <<<"$first_line"
  [ "${verb:-}" = "failed" ] || continue
  # A transport error is not proof of recovery. Unloaded transient units have
  # LoadState=not-found/ActiveState=inactive and can be cleared normally.
  if ! state="$(systemctl show --property=ActiveState --value "$unit" 2>/dev/null)"; then
    continue
  fi
  if [ -z "$state" ] || [ "$state" = failed ]; then
    continue
  fi
  clear_marker "$marker" "$unit is no longer failed"
done
