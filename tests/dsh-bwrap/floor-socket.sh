#!/usr/bin/env bash
# tests/dsh-bwrap/floor-socket.sh: dsh-bwrap's one hole in its /run/user mask,
# the factory floor's control socket (pkgs/dsh/dsh-bwrap.sh).
#
#   ~/.local/bin/runtime-test -- bash tests/dsh-bwrap/floor-socket.sh <dsh-bwrap>
#
# <dsh-bwrap> is the runner to test, e.g. "$(nix build .#dsh.runner
# --print-out-paths)/bin/dsh-bwrap". It refuses to run outside runtime-test
# (pid 1 must be bwrap, and /run/user/<uid> must be the wrapper's own, with no
# bus and no systemd/private), because it makes sockets under /run/user/<uid>.
#
# It makes, in the private runtime dir, a listening floor socket
# agency-floor/floor.sock, a second profile's agency-floor/other.sock, a decoy
# herdr-core/default.sock and a symlink agency-floor/link.sock to the decoy.
# Then it runs a probe through dsh-bwrap with dsh's own workspace-write profile
# and checks, case by case, what the probe's bash sees:
#   1. no floor variables: nothing under /run/user/<uid>;
#   2. a floor worker (AGENCY_FLOOR_SOCKET + AGENCY_FLOOR_LAUNCH_FILE): only
#      floor.sock, as a socket it can connect to and read the floor's answer
#      from; its rm of the socket and a file it plants beside it never reach
#      the host;
#   3. AGENCY_FLOOR_SOCKET alone (a hand-started dsh): nothing;
#   4. AGENCY_FLOOR_SOCKET at the decoy, or at agency-floor/../herdr-core/…,
#      or at the symlink: nothing;
#   5. a socket of another owner's shape (not a socket: a plain file): nothing.
# It prints one "ok:" line per case and "FLOOR SOCKET OK" at the end.
set -euo pipefail

die() { echo "FAIL: $*" >&2; exit 1; }
[ "$#" -eq 1 ] || die "usage: floor-socket.sh <dsh-bwrap>"
runner=$1
[ -x "$runner" ] || die "$runner is not executable"
[ "$(cat /proc/1/comm 2>/dev/null)" = bwrap ] || die "run me under ~/.local/bin/runtime-test (pid 1 is not bwrap)"
uid=$(id -u)
rt="/run/user/$uid"
[ ! -e "$rt/bus" ] && [ ! -e "$rt/systemd/private" ] || die "$rt looks like the live runtime dir"
command -v python3 >/dev/null || die "python3 is not on PATH"

work=$(mktemp -d /var/tmp/dsh-bwrap-floor-XXXXXX)
ws="$work/ws"
mkdir -p "$ws" "$rt/agency-floor" "$rt/herdr-core"
chmod 0700 "$rt/agency-floor" "$rt/herdr-core"
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
  rm -rf -- "$work" "$rt/agency-floor" "$rt/herdr-core"
}
trap cleanup EXIT

# A listener that answers every connection with one line naming itself.
listen() {
  python3 - "$1" "$2" <<'PY' &
import os, socket, sys
path, word = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(path)
os.chmod(path, 0o600)
s.listen(8)
while True:
    c, _ = s.accept()
    c.sendall((word + "\n").encode())
    c.close()
PY
  pids+=("$!")
}
listen "$rt/agency-floor/floor.sock" floor
listen "$rt/agency-floor/other.sock" other
listen "$rt/herdr-core/default.sock" herdr
ln -s ../herdr-core/default.sock "$rt/agency-floor/link.sock"
: >"$rt/agency-floor/plain.sock"
for s in agency-floor/floor.sock agency-floor/other.sock herdr-core/default.sock; do
  for _ in $(seq 50); do [ -S "$rt/$s" ] && break; sleep 0.1; done
  [ -S "$rt/$s" ] || die "listener $rt/$s did not start"
done

# The probe: what the sandboxed bash sees under /run/user/<uid>, and the answer
# of each socket it can connect to.
probe=$(cat <<'SH'
rt=$1
find "$rt" -mindepth 1 -printf '%P\n' 2>/dev/null | sort
for s in agency-floor/floor.sock agency-floor/other.sock herdr-core/default.sock agency-floor/link.sock; do
  if [ -S "$rt/$s" ]; then
    printf 'connect %s: %s\n' "$s" "$(python3 -c 'import socket,sys
c=socket.socket(socket.AF_UNIX); c.connect(sys.argv[1]); print(c.recv(64).decode().strip())' "$rt/$s" 2>&1)"
  fi
done
# The directory bwrap made for the bind lives in the sandbox's own tmpfs, so
# a file planted there never reaches the host; the socket is a mount point,
# so it cannot be removed or replaced. The host side checks both.
touch "$rt/agency-floor/planted" 2>/dev/null || true
rm -f "$rt/agency-floor/floor.sock" 2>/dev/null || true
SH
)
# dsh's own bwrap profile in workspace-write (see the header of dsh-bwrap.sh).
run() {
  env "$@" "$runner" --ro-bind / / --dev /dev --unshare-pid --proc /proc --die-with-parent \
    --tmpfs /tmp --bind "$ws" "$ws" -- bash -c "$probe" probe "$rt"
}

expect_nothing() {
  local name=$1 out
  shift
  out=$(run "$@")
  [ -z "$out" ] || die "$name: the sandbox saw under $rt: $(tr '\n' ';' <<<"$out")"
  echo "ok: $name: nothing under $rt"
}

expect_nothing "no floor variables"
out=$(run AGENCY_FLOOR_SOCKET="$rt/agency-floor/floor.sock" AGENCY_FLOOR_LAUNCH_FILE="$work/token")
want=$(printf '%s\n' 'agency-floor' 'agency-floor/floor.sock' 'connect agency-floor/floor.sock: floor')
[ "$out" = "$want" ] || die "a floor worker: expected exactly floor.sock, connectable; got: $(tr '\n' ';' <<<"$out")"
[ -S "$rt/agency-floor/floor.sock" ] && [ ! -e "$rt/agency-floor/planted" ] \
  || die "a floor worker: the host's agency-floor changed (floor.sock gone or a planted file)"
echo "ok: a floor worker: only agency-floor/floor.sock, connect answers 'floor'; the host's agency-floor is unchanged"
expect_nothing "AGENCY_FLOOR_SOCKET without AGENCY_FLOOR_LAUNCH_FILE" AGENCY_FLOOR_SOCKET="$rt/agency-floor/floor.sock"
expect_nothing "the herdr-core decoy" AGENCY_FLOOR_SOCKET="$rt/herdr-core/default.sock" AGENCY_FLOOR_LAUNCH_FILE="$work/token"
expect_nothing "a path through .." AGENCY_FLOOR_SOCKET="$rt/agency-floor/../herdr-core/default.sock" AGENCY_FLOOR_LAUNCH_FILE="$work/token"
expect_nothing "a symlink in agency-floor" AGENCY_FLOOR_SOCKET="$rt/agency-floor/link.sock" AGENCY_FLOOR_LAUNCH_FILE="$work/token"
expect_nothing "a plain file named .sock" AGENCY_FLOOR_SOCKET="$rt/agency-floor/plain.sock" AGENCY_FLOOR_LAUNCH_FILE="$work/token"
[ ! -e "$rt/agency-floor/planted" ] || die "the sandbox planted a file in $rt/agency-floor"
echo "FLOOR SOCKET OK"
