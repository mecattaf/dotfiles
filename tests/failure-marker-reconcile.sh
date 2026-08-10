#!/usr/bin/env bash
set -euo pipefail

reconciler="${FAILURE_MARKER_RECONCILER:?FAILURE_MARKER_RECONCILER must be set}"
root="$(mktemp -d)"
marker_dir="$root/markers"
fake_bin="$root/bin"
mkdir -p "$marker_dir" "$fake_bin"

printf '#!%s\n' "${BASH:?BASH must be set}" >"$fake_bin/systemctl"
cat >>"$fake_bin/systemctl" <<'EOF'
set -euo pipefail
if [ "${1:-}" = "--user" ]; then
  [[ "$*" == *"--machine=1000@.host"* ]]
  if [ "${FAKE_USER_QUERY_ERROR:-0}" = "1" ]; then
    exit 1
  fi
  if [ -n "${FAKE_USER_FAILED:-}" ]; then
    printf '%s loaded failed failed\n' "$FAKE_USER_FAILED"
  fi
  exit 0
fi
if [ "${1:-}" = "is-failed" ]; then
  unit="${*: -1}"
  [ "$unit" = "broken.service" ]
  exit
fi
exit 9
EOF
chmod +x "$fake_bin/systemctl"

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

FAKE_USER_FAILED=tally-campaign-poll.service bash "$reconciler"
test -e "$marker_dir/user-unit-failure"
test ! -e "$marker_dir/recovered.service"
test -e "$marker_dir/broken.service"
test -e "$marker_dir/coredump"

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
