#!/usr/bin/env bash
set -euo pipefail

notifier="${FAILURE_NOTIFIER:?FAILURE_NOTIFIER must be set}"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
marker_dir="$root/markers"
fake_bin="$root/bin"
journal_log="$root/journal"
podman_calls="$root/podman-calls"
mkdir -p "$marker_dir" "$fake_bin"
: >"$journal_log"

# The fake podman answers `container inspect` from FAKE_HEALTH ("<name>
# <status>"), or fails like podman does for a container that is gone.
printf '#!%s\n' "${BASH:?BASH must be set}" >"$fake_bin/podman"
cat >>"$fake_bin/podman" <<'EOF'
set -euo pipefail
printf '%s\n' "$*" >>"$PODMAN_CALLS"
[ "$1" = container ] && [ "$2" = inspect ]
if [ "${FAKE_PODMAN_ERROR:-0}" = 1 ]; then
  echo 'Error: no such container' >&2
  exit 125
fi
printf '%s\n' "$FAKE_HEALTH"
EOF
printf '#!%s\n' "$BASH" >"$fake_bin/logger"
printf '%s\n' 'cat >>"$JOURNAL_LOG"' >>"$fake_bin/logger"
chmod +x "$fake_bin/podman" "$fake_bin/logger"

export PATH="$fake_bin:$PATH"
export FAILURE_MARKER_DIR="$marker_dir"
export JOURNAL_LOG="$journal_log"
export PODMAN_CALLS="$podman_calls"

ctr=25996b6ff72ade3f5c9f869fec62e8af57f989682063f1c25c809dd305779232
probe="$ctr-4e5488c32440d6fe"

# An ordinary unit keeps the marker grammar the reconciler parses, and podman
# is never asked about it.
bash "$notifier" broken
grep -Eqx 'broken failed at [0-9-]{10} [0-9:]{5} — journalctl -u broken -b' "$marker_dir/broken"
test ! -e "$podman_calls"
grep -Fqx 'DECISION=marker-written' "$journal_log"

# A slash in an instance name cannot escape the marker directory.
bash "$notifier" 'odd/name'
test -f "$marker_dir/odd_name"

# A probe that fails while the container is still healthy, or still inside its
# start period, writes nothing; the journal keeps the decision.
for status in healthy starting; do
  : >"$journal_log"
  FAKE_HEALTH="halogen $status" bash "$notifier" "$probe"
  test ! -e "$marker_dir/$probe"
  grep -Fqx 'DECISION=probe-below-verdict' "$journal_log"
  grep -Fqx "HEALTH_STATUS=$status" "$journal_log"
  grep -Fqx 'CONTAINER=halogen' "$journal_log"
done
grep -Fqx "container inspect --format {{.Name}} {{.State.Health.Status}} $ctr" "$podman_calls"

# The unhealthy verdict is surfaced and names the container, without breaking
# the "<unit> failed at" first line the reconciler reads.
: >"$journal_log"
FAKE_HEALTH='halogen unhealthy' bash "$notifier" "$probe"
grep -Fq "$probe failed at " "$marker_dir/$probe"
grep -Fq '— container halogen is unhealthy — journalctl -u '"$probe"' -b' "$marker_dir/$probe"
grep -Fqx 'DECISION=marker-written' "$journal_log"
read -r unit verb _ <"$marker_dir/$probe"
[ "$unit" = "$probe" ] && [ "$verb" = failed ]
rm -f -- "$marker_dir/$probe"

# A container without a health status is surfaced, not silently dropped.
FAKE_HEALTH='halogen' bash "$notifier" "$probe"
grep -Fq '— container halogen is without a health status — ' "$marker_dir/$probe"
rm -f -- "$marker_dir/$probe"

# Fail open: when podman cannot answer, the probe failure is surfaced as a
# plain unit failure.
FAKE_PODMAN_ERROR=1 bash "$notifier" "$probe"
grep -Eqx "$probe failed at [0-9-]{10} [0-9:]{5} — journalctl -u $probe -b" "$marker_dir/$probe"
rm -f -- "$marker_dir/$probe"

# A host with podman disabled has no podman to ask: the same.
printf '#!%s\nexit 127\n' "$BASH" >"$fake_bin/podman"
bash "$notifier" "$probe"
test -f "$marker_dir/$probe"

# A unit name that only resembles a probe (too short an id) never reaches podman.
rm -f -- "$podman_calls"
bash "$notifier" "25996b6ff72a-4e5488c32440d6fe"
test -f "$marker_dir/25996b6ff72a-4e5488c32440d6fe"
test ! -e "$podman_calls"

echo "failure-notify: ok"
