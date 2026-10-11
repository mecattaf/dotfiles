#!/usr/bin/env bash
# home/dot_local/bin/screenshot on the client (2026-10-11): the capture goes to
# a hidden spool, every spooled file is pushed to strix:~/Pictures/Screenshots,
# and a local file is deleted only once the strix holds the same bytes. On
# any other host the file lands in ~/Pictures/Screenshots and nothing is sent.
#
# Hermetic: the "strix" is a second temporary home reached through a fake ssh
# that runs the remote command locally (real rsync --server, real sha256sum);
# grim, wl-copy, swaymsg, slurp, satty, hostname and date are fakes.
#
#   test-spool.sh <screenshot>
set -euo pipefail

[[ $# -eq 1 && -f "$1" ]] || { echo "usage: test-spool.sh <screenshot>" >&2; exit 2; }
script="$1"

root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
bin="$root/bin"
client_home="$root/client"
strix_home="$root/strix"
mkdir -p "$bin" "$client_home" "$strix_home"
spool="$client_home/.local/state/screenshot-spool"
remote="$strix_home/Pictures/Screenshots"
ssh_log="$root/ssh.log"
: > "$ssh_log"

fake() { # $1 = name; body on stdin
  { printf '#!%s\n' "$(command -v bash)"; cat; } > "$bin/$1"
  chmod +x "$bin/$1"
}
fake hostname <<'EOF'
printf '%s\n' "$FAKE_HOST"
EOF
fake date <<'EOF'
printf '%s\n' "$FAKE_DATE"
EOF
fake grim <<'EOF'
printf '%s' "$FAKE_IMAGE" > "${!#}"
EOF
fake wl-copy <<'EOF'
cat > "$FAKE_CLIPBOARD"
EOF
fake swaymsg <<'EOF'
printf '%s\n' '[{"name": "eDP-1", "focused": true}]'
EOF
fake slurp <<'EOF'
[[ -z "${FAKE_SLURP_CANCEL:-}" ]] || exit 1
printf '0,0 10x10\n'
EOF
fake satty <<'EOF'
exit 0
EOF
# ssh <options> strix <command...>: like sshd, join the words and hand them to
# the login shell, here in the fake strix's home.
fake ssh <<'EOF'
while [[ "${1:-}" == -o ]]; do shift 2; done
host="$1"; shift
printf '%s %s\n' "$host" "$*" >> "$FAKE_SSH_LOG"
[[ -z "${FAKE_SSH_DOWN:-}" ]] || { echo "ssh: connect to host $host: No route to host" >&2; exit 255; }
[[ "$host" == strix ]] || exit 255
cd "$FAKE_STRIX_HOME"
HOME="$FAKE_STRIX_HOME" exec bash -c "$*"
EOF

run() { # $1 = host, $2 = date, $3 = mode; extra fake settings come from the caller's env
  local host="$1" when="$2" mode="$3"
  env HOME="$client_home" XDG_STATE_HOME="$client_home/.local/state" \
    PATH="$bin:$PATH" SWAYSOCK=fake FAKE_HOST="$host" FAKE_DATE="$when" \
    FAKE_IMAGE="${FAKE_IMAGE:-image $when}" FAKE_CLIPBOARD="$root/clipboard" \
    FAKE_SSH_LOG="$ssh_log" FAKE_STRIX_HOME="$strix_home" \
    bash "$script" "$mode"
}
name() { printf 'Screenshot from %s.png' "$1"; }
spooled() { find "$spool" -maxdepth 1 -type f ! -name '.*' -printf '%f\n' | sort; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. Strix reachable: pushed, verified, removed; clipboard kept; no ~/Pictures.
run client "2026-10-11 10-00-01" screen 2>"$root/err1"
[[ "$(<"$remote/$(name '2026-10-11 10-00-01')")" == "image 2026-10-11 10-00-01" ]] \
  || fail "screen capture not on the strix"
[[ -z "$(spooled)" ]] || fail "spool not empty after a verified push: $(spooled)"
[[ -z "$(find "$spool/.pending" -type f)" ]] || fail ".pending not empty"
[[ "$(<"$root/clipboard")" == "image 2026-10-11 10-00-01" ]] || fail "clipboard copy lost"
[[ ! -e "$client_home/Pictures" ]] || fail "Pictures created in the client home"
echo "ok 1 pushed and removed"

# 2. Strix unreachable: the file stays in the hidden spool, nothing is lost.
FAKE_SSH_DOWN=1 run client "2026-10-11 10-00-02" screen 2>"$root/err2"
[[ "$(spooled)" == "$(name '2026-10-11 10-00-02')" ]] || fail "unreachable: spool holds '$(spooled)'"
[[ ! -e "$remote/$(name '2026-10-11 10-00-02')" ]] || fail "unreachable: file on the strix"
grep -q "kept in $spool" "$root/err2" || fail "unreachable: no 'kept in' message"
echo "ok 2 kept while the strix is down"

# 3. The next run, even a cancelled one, takes the leftover with it.
FAKE_SLURP_CANCEL=1 run client "2026-10-11 10-00-03" area 2>"$root/err3"
[[ -z "$(spooled)" ]] || fail "leftover not pushed: $(spooled)"
[[ "$(<"$remote/$(name '2026-10-11 10-00-02')")" == "image 2026-10-11 10-00-02" ]] \
  || fail "leftover content differs on the strix"
echo "ok 3 leftover goes with the next run"

# 4. A different file of the same name on the strix is never replaced, and the
#    local one is kept. 5. An identical one already there: local is removed.
printf 'remote bytes' > "$remote/$(name conflict)"
printf 'local bytes' > "$spool/$(name conflict)"
printf 'same bytes' > "$remote/$(name same)"
printf 'same bytes' > "$spool/$(name same)"
run client "2026-10-11 10-00-04" screen 2>"$root/err4"
[[ "$(<"$remote/$(name conflict)")" == "remote bytes" ]] || fail "strix file overwritten"
[[ "$(<"$spool/$(name conflict)")" == "local bytes" ]] || fail "conflicting local file lost"
[[ "$(spooled)" == "$(name conflict)" ]] || fail "after conflict run spool holds '$(spooled)'"
grep -q "the strix has no identical copy" "$root/err4" || fail "conflict not reported"
echo "ok 4 no overwrite on the strix, local kept"
echo "ok 5 identical copy on the strix: local removed"
rm -f -- "$spool/$(name conflict)"

# 6. A capture left in .pending while another run is capturing stays put;
#    once nobody is capturing, the next run adopts and pushes it.
printf 'orphan' > "$spool/.pending/$(name orphan)"
flock -s "$spool/.capture.lock" sleep 3 &
holder=$!
sleep 0.5
run client "2026-10-11 10-00-06" screen 2>"$root/err6"
[[ -f "$spool/.pending/$(name orphan)" ]] || fail "pending file taken while a capture was in progress"
[[ -f "$remote/$(name '2026-10-11 10-00-06')" ]] || fail "own capture not pushed"
wait "$holder"
run client "2026-10-11 10-00-07" screen 2>"$root/err7"
[[ ! -e "$spool/.pending/$(name orphan)" ]] || fail "orphan not adopted"
[[ "$(<"$remote/$(name orphan)")" == "orphan" ]] || fail "orphan not on the strix"
[[ -z "$(spooled)" ]] || fail "spool not empty: $(spooled)"
echo "ok 6 orphaned capture adopted only when no capture runs"

# 7. Any other host: ~/Pictures/Screenshots as before, no spool, no ssh.
: > "$ssh_log"
other_state="$root/other-state"
env HOME="$root/other" XDG_STATE_HOME="$other_state" PATH="$bin:$PATH" SWAYSOCK=fake \
  FAKE_HOST=strix FAKE_DATE="2026-10-11 10-00-08" FAKE_IMAGE="strix image" \
  FAKE_CLIPBOARD="$root/clipboard" FAKE_SSH_LOG="$ssh_log" FAKE_STRIX_HOME="$strix_home" \
  bash "$script" screen
[[ "$(<"$root/other/Pictures/Screenshots/$(name '2026-10-11 10-00-08')")" == "strix image" ]] \
  || fail "other host: not saved under ~/Pictures/Screenshots"
[[ ! -e "$other_state/screenshot-spool" ]] || fail "other host: spool created"
[[ ! -s "$ssh_log" ]] || fail "other host: ssh called: $(<"$ssh_log")"
echo "ok 7 other hosts unchanged"
