#!/usr/bin/env bash
set -euo pipefail

reconciler="${FAILURE_MARKER_RECONCILER:?FAILURE_MARKER_RECONCILER must be set}"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
marker_dir="$root/markers"
fake_bin="$root/bin"
mkdir -p "$marker_dir" "$fake_bin"

printf '#!%s\n' "${BASH:?BASH must be set}" >"$fake_bin/systemctl"
cat >>"$fake_bin/systemctl" <<'EOF'
set -euo pipefail
if [ "${1:-}" = "--user" ]; then
  [[ "$*" != *"--machine="* ]]
  [ "$XDG_RUNTIME_DIR" = /run/user/1000 ]
  [ "$DBUS_SESSION_BUS_ADDRESS" = unix:path=/run/user/1000/systemd/private ]
  if [ "${FAKE_USER_QUERY_ERROR:-0}" = "1" ]; then
    exit 1
  fi
  if [ -n "${FAKE_USER_FAILED:-}" ]; then
    printf '%s loaded failed failed\n' "$FAKE_USER_FAILED"
  fi
  exit 0
fi
if [ "${1:-}" = "show" ]; then
  unit="${*: -1}"
  case "$unit" in
    broken.service) echo failed ;;
    unreachable.service) exit 1 ;;
    empty.service) : ;;
    *) echo inactive ;;
  esac
  exit 0
fi
exit 9
EOF
chmod +x "$fake_bin/systemctl"

# No root or live user manager is needed for this regression test.
printf '#!%s\n' "$BASH" >"$fake_bin/runuser"
cat >>"$fake_bin/runuser" <<'EOF'
set -eu
[ "$1" = -u ]; [ -n "$2" ]; [ "$3" = -- ]
shift 3
exec "$@"
EOF
printf '#!%s\n' "$BASH" >"$fake_bin/id"
printf '%s\n' 'echo test-user' >>"$fake_bin/id"
chmod +x "$fake_bin/runuser" "$fake_bin/id"

printf '#!%s\n' "${BASH:?BASH must be set}" >"$fake_bin/logger"
cat >>"$fake_bin/logger" <<'EOF'
cat >/dev/null
EOF
chmod +x "$fake_bin/logger"

export PATH="$fake_bin:$PATH"
export FAILURE_MARKER_DIR="$marker_dir"
export USER_MANAGER_UIDS="1000"

printf '%s\n' '2026-08-10 — 1 new user unit failure(s)' >"$marker_dir/user-unit-failure"
printf '%s\n' 'recovered.service failed at 2026-08-10 00:10 — journalctl' \
  >"$marker_dir/recovered.service"
printf '%s\n' 'broken.service failed at 2026-08-10 00:10 — journalctl' \
  >"$marker_dir/broken.service"
printf '%s\n' '2026-08-10 — 1 new coredump(s)' >"$marker_dir/coredump"
printf '%s\n' 'unreachable.service failed at 2026-09-16 11:04 — journalctl' >"$marker_dir/unreachable.service"
printf '%s\n' 'empty.service failed at 2026-09-16 11:04 — journalctl' >"$marker_dir/empty.service"

FAKE_USER_FAILED=tally-campaign-poll.service bash "$reconciler"
test -e "$marker_dir/user-unit-failure"
test ! -e "$marker_dir/recovered.service"
test -e "$marker_dir/broken.service"
test -e "$marker_dir/coredump"
test -e "$marker_dir/unreachable.service"
test -e "$marker_dir/empty.service"

# Query failure is fail-open: never erase an incident when current health is
# unknown.
FAKE_USER_QUERY_ERROR=1 FAKE_USER_FAILED= bash "$reconciler"
test -e "$marker_dir/user-unit-failure"

# A later successful unit invocation removes it from the manager's failed set;
# the next reconciliation clears only that recovered aggregate marker.
FAKE_USER_QUERY_ERROR=0 FAKE_USER_FAILED= bash "$reconciler"
test ! -e "$marker_dir/user-unit-failure"
test -e "$marker_dir/broken.service"
test -e "$marker_dir/coredump"
