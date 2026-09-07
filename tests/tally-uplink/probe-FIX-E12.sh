#!/usr/bin/env bash
# FIX-E12 (spec id `uplink-has-no-trigger`, dotfiles#351, D-E24) — the oracle for
# the uplink's WAKE.
#
# WHAT IT PROVES. Before this unit, tally-uplink.service had been failed for 7h
# with TriggeredBy=, WantedBy=, RequiredBy= and Wants= all empty, no .timer file,
# no reverse dependency and `wakes = 1`: nothing on the box could ever start it
# again. This probe asserts, from a fresh checkout and out of the TREE only, that
# the box now owns the trigger — and that giving it one did not turn the uplink
# into a loop.
#
#   S1 the coordinator DECLARES systemd.user.timers.tally-uplink and its Timer
#      block is non-empty, in the monotonic form: OnUnitInactiveSec set (the
#      period runs from the END of the previous pass, failures included, so wakes
#      cannot pile up behind a red run), OnActiveSec equal to it, no OnCalendar,
#      Persistent false, Unit = tally-uplink.service, and armed by timers.target.
#   S2 the WORKER declares no such timer (one uplink per box that serves a
#      kernel; the worker twin is a row that kernel serves).
#   S3 the SERVICE is untouched: Type=oneshot, `--wakes 1` in the rendered argv,
#      and still no Install section of its own.
#   S4 `nix build .#checks.x86_64-linux.tally-uplink-topology -L` -> rc 0, the
#      check that asserts all of the above over the rendered units.
#   S5 `nix flake check` -> rc 0: the repository stays green.
#
# INDEPENDENT OF THE LIVE BOX. Every clause is an evaluation or a build of this
# tree. Nothing is switched, started, stopped or enabled; no seat capacity is
# consulted; the deployed lake is never contacted (the uplink keeps exiting 1 on
# its 5xx until the `tally-lake` pin is bumped at the switch — FIX-E04/U-D19 —
# and that is deliberately NOT this unit's business, nor this probe's); no
# credential is read or printed; nothing under ~/.local/state is touched.
#
# Usage: bash tests/tally-uplink/probe-FIX-E12.sh [repo-path]
# rc 0 = every clause passed. rc 1 = a clause failed. rc 2 = the probe could not run.
set -uo pipefail

repo="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$repo" || { echo "FAIL: cannot cd $repo"; exit 2; }
command -v nix >/dev/null || { echo "FAIL: no nix on PATH"; exit 2; }

fails=0
ok()   { printf 'ok   %s\n' "$*"; }
bad()  { printf 'FAIL %s\n' "$*"; fails=$((fails + 1)); }

coord=".#nixosConfigurations.coordinator.config.home-manager.users.tom"
worker=".#nixosConfigurations.worker.config.home-manager.users.tom"

# `nix eval --raw ... --apply` with an explicit toString/toJSON, so a value that
# does not exist is a non-zero rc here rather than the string "null".
ev() { nix eval --raw "$1" --apply "$2" 2>/dev/null; }

# ---- S1: the timer is declared on the coordinator, and it is a monotonic clock.
timer_json="$(ev "${coord}.systemd.user.timers.tally-uplink.Timer" 'builtins.toJSON')"
if [ -z "$timer_json" ] || [ "$timer_json" = "{}" ]; then
  bad "S1 coordinator systemd.user.timers.tally-uplink.Timer is empty or absent"
else
  ok "S1 Timer = $timer_json"
fi

check_eq() { # label expr expected
  local got; got="$(ev "$2" 'v: builtins.toJSON v')"
  if [ "$got" = "$3" ]; then ok "$1 = $3"; else bad "$1: expected $3, got '${got}'"; fi
}
check_eq "S1 OnUnitInactiveSec" "${coord}.systemd.user.timers.tally-uplink.Timer.OnUnitInactiveSec" '"5min"'
check_eq "S1 OnActiveSec"       "${coord}.systemd.user.timers.tally-uplink.Timer.OnActiveSec"       '"5min"'
check_eq "S1 Persistent"        "${coord}.systemd.user.timers.tally-uplink.Timer.Persistent"        'false'
check_eq "S1 Timer.Unit"        "${coord}.systemd.user.timers.tally-uplink.Timer.Unit"              '"tally-uplink.service"'
# the two clauses below are shapes rather than equalities, so they are read
# with their own `--apply` instead of check_eq.
got="$(ev "${coord}.systemd.user.timers.tally-uplink.Timer" 't: if t ? OnCalendar then "yes" else "no"')"
if [ "$got" = "no" ]; then ok "S1 no OnCalendar (monotonic form only)"; else bad "S1 OnCalendar present: '$got'"; fi
got="$(ev "${coord}.systemd.user.timers.tally-uplink" \
  'u: if builtins.elem "timers.target" (u.Install.WantedBy or []) then "yes" else "no"')"
if [ "$got" = "yes" ]; then ok "S1 Install.WantedBy contains timers.target"; else bad "S1 Install.WantedBy lacks timers.target: '$got'"; fi
# the cadence IS the drain's own, read from the drain's declaration.
got="$(ev "${coord}.systemd.user.timers" \
  't: if t.tally-uplink.Timer.OnUnitInactiveSec == t.tally-drain.Timer.OnUnitActiveSec then "yes" else "no"')"
if [ "$got" = "yes" ]; then ok "S1 wake period == tally-drain cadence"; else bad "S1 wake period != tally-drain cadence: '$got'"; fi

# ---- S2: the worker declares no uplink timer (and no uplink service).
got="$(ev "${worker}.systemd.user.timers" 't: if t ? tally-uplink then "yes" else "no"')"
if [ "$got" = "no" ]; then ok "S2 worker declares no tally-uplink.timer"; else bad "S2 worker declares a tally-uplink timer: '$got'"; fi
got="$(ev "${worker}.systemd.user.services" 's: if s ? tally-uplink then "yes" else "no"')"
if [ "$got" = "no" ]; then ok "S2 worker declares no tally-uplink.service"; else bad "S2 worker declares tally-uplink.service: '$got'"; fi

# ---- S3: the service is the same oneshot, one wake, no Install of its own.
check_eq "S3 Service.Type" "${coord}.systemd.user.services.tally-uplink.Service.Type" '"oneshot"'
got="$(ev "${coord}.systemd.user.services.tally-uplink" 'u: if u ? Install then "yes" else "no"')"
if [ "$got" = "no" ]; then ok "S3 service carries no Install section"; else bad "S3 service grew an Install section: '$got'"; fi
got="$(ev "${coord}.systemd.user.services.tally-uplink.Service.ExecStart" \
  'e: let s = if builtins.isList e then builtins.concatStringsSep " " e else e; in if builtins.match ".*--wakes 1( .*|)" s != null then "yes" else s')"
if [ "$got" = "yes" ]; then ok "S3 rendered ExecStart still says --wakes 1"; else bad "S3 ExecStart lost '--wakes 1': '$got'"; fi

# ---- S4: the topology check builds.
if nix build .#checks.x86_64-linux.tally-uplink-topology -L; then
  ok "S4 nix build .#checks.x86_64-linux.tally-uplink-topology"
else
  bad "S4 tally-uplink-topology did not build"
fi

# ---- S5: the repository stays green.
if nix flake check; then
  ok "S5 nix flake check"
else
  bad "S5 nix flake check is not green"
fi

if [ "$fails" -eq 0 ]; then
  echo "PROBE FIX-E12: PASS"
  exit 0
fi
echo "PROBE FIX-E12: FAIL ($fails clause(s))"
exit 1
