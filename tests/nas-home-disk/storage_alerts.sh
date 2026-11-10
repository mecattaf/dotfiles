#!/usr/bin/env bash
# Behavioural check of hosts/nas/storage-alerts.nix (O1 PR-1): the NAS's own
# sensor and onFire scripts, driven through the real tripwire-poll, in the
# build sandbox. No mount, disk or journal of the build host is changed.
set -euo pipefail

poll_bin="${TRIPWIRE_POLL:?}"
reconciler="${FAILURE_MARKER_RECONCILER:?}"
reporter="${FAILURE_MARKER_REPORTER:?}"
read -r -a usage_names <<<"${USAGE_NAMES:?}"

root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
export FAILURE_MARKER_DIR="$root/markers"
export HOME="$root/home"
mkdir -p "$HOME" "$root/bin"

fail() {
  echo "storage-alerts: $*" >&2
  exit 1
}

# The reconciler must never need systemctl for these markers.
{
  printf '#!%s\n' "${BASH:?}"
  cat <<'EOF'
echo "systemctl called: $*" >&2
exit 9
EOF
} >"$root/bin/systemctl"
chmod +x "$root/bin/systemctl"

sensor_of() { local v="SENSOR_${1//-/_}"; printf '%s' "${!v:?no sensor for $1}"; }
onfire_of() { local v="ONFIRE_${1//-/_}"; printf '%s' "${!v:?no onFire for $1}"; }

# poll <tripwire> <sensor> <onfire> <threshold> <rearm>
poll() {
  mkdir -p "$root/state/$1"
  STATE_DIRECTORY="$root/state/$1" TRIPWIRE_NAME="$1" TRIPWIRE_SENSOR="$2" \
    TRIPWIRE_ONFIRE="$3" TRIPWIRE_THRESHOLD="$4" TRIPWIRE_REARM="$5" \
    TRIPWIRE_RENOTIFY=86400 TRIPWIRE_VALUE_FIELD=VALUE \
    "$poll_bin" 2>>"$root/poll.log"
}

# Baseline the once-per-user reporter while the marker dir is still empty.
mkdir -p "$FAILURE_MARKER_DIR"
[ -z "$(bash "$reporter" "$FAILURE_MARKER_DIR")" ] || fail "reporter spoke on an empty dir"

# 1. Every usage sensor emits one line in the poll's grammar. The kind must not
#    carry a path: tripwire-poll rejects "/" in a kind.
for name in "${usage_names[@]}"; do
  short="${name#disk-}"
  line="$("$(sensor_of "$name")")"
  [[ "$line" =~ ^[0-9]+\ (disk|unmounted):${short}$ ]] || fail "$name sensor printed '$line'"
  poll "$name" "$(sensor_of "$name")" "$(onfire_of "$name")" 101 96 \
    || fail "$name poll rejected '$line'"
done
[[ "$("$(sensor_of disk-root)")" =~ ^[0-9]+\ disk:root$ ]] || fail "/ must always be measured"
[ -z "$(ls -A "$FAILURE_MARKER_DIR")" ] || fail "a nominal poll wrote a marker"

# 2. A fire writes the marker the login banner prints, readable by tom.
poll disk-root-fire "$(sensor_of disk-root)" "$(onfire_of disk-root)" 0 -5
marker="$FAILURE_MARKER_DIR/disk-root"
[ -f "$marker" ] || fail "fire wrote no disk-root marker"
[ "$(stat -c %a "$marker")" = 644 ] || fail "marker mode $(stat -c %a "$marker")"
first="$(head -n 1 "$marker")"
[[ "$first" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}\ \ eMMC\ root\ /\ is\ [0-9]+%\ full\ \(alert\ at\ 0%,\ episode\ disk:root-[0-9]+\)$ ]] \
  || fail "disk-root first line: $first"
grep -q 'check: df -h /;' "$marker" || fail "disk-root marker has no check line"
grep -q 'bind-mount /' "$marker" || fail "disk-root marker has no hidden-files hint"

# 3. Still over and inside the renotify window: no second fire.
before="$(sha256sum "$marker")"
poll disk-root-fire "$(sensor_of disk-root)" "$(onfire_of disk-root)" 0 -5
[ "$(sha256sum "$marker")" = "$before" ] || fail "re-fired inside the renotify window"
grep -q '^armed=0$' "$root/state/disk-root-fire/state" || fail "fire did not disarm"

# 4. The presence sensor counts what is missing in the sandbox (at least the
#    data mounts) and its marker names them.
line="$("$(sensor_of nas-mounts)")"
[[ "$line" =~ ^[1-9][0-9]*\ mounts$ ]] || fail "nas-mounts sensor printed '$line'"
poll nas-mounts "$(sensor_of nas-mounts)" "$(onfire_of nas-mounts)" 1 1
marker="$FAILURE_MARKER_DIR/nas-mounts"
[ -f "$marker" ] || fail "nas-mounts fired no marker"
first="$(head -n 1 "$marker")"
[[ "$first" == *" required mount(s) missing: "*"/mnt/nas"*"(episode mounts-"* ]] \
  || fail "nas-mounts first line: $first"

# 5. rearm = 1 re-arms on the first healthy (0) sample; rearm = 0 never would.
printf '#!%s\necho "0 mounts"\n' "$BASH" >"$root/bin/healthy"
chmod +x "$root/bin/healthy"
poll nas-mounts "$root/bin/healthy" "$root/bin/no-onfire-expected" 1 1
grep -q '^armed=1$' "$root/state/nas-mounts/state" || fail "a healthy sample did not re-arm"

# 6. The reconciler keeps both markers (they are events, not "<unit> failed"),
#    and the reporter prints each episode once.
PATH="$root/bin:$PATH" USER_MANAGER_UIDS="" FAILURE_MARKER_DIR="$FAILURE_MARKER_DIR" \
  bash "$reconciler"
[ -f "$FAILURE_MARKER_DIR/disk-root" ] && [ -f "$FAILURE_MARKER_DIR/nas-mounts" ] \
  || fail "the reconciler removed a storage marker"
shown="$(bash "$reporter" "$FAILURE_MARKER_DIR")"
[ "$(printf '%s\n' "$shown" | grep -c .)" = 2 ] || fail "reporter showed: $shown"
[ -z "$(bash "$reporter" "$FAILURE_MARKER_DIR")" ] || fail "reporter repeated an episode"

echo "storage-alerts: ok"
