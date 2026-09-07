#!/usr/bin/env bash
# U-D19 DF-SWITCH (dotfiles#322) — THE NEGATIVE CONTROL.
#
#   bash tools/u-d19-worker-negative-control.sh
#
# The card's mutation hint is not a code mutation:
#
#   "not a code mutation: the negative control is the probe on the worker box,
#    which must report the units absent (unswitched)"
#
# So this is the mutation, and it is a MEASUREMENT, not an edit. The switch's
# post-conditions — tally-kernel.service active with a /nix/store FragmentPath,
# tally-uplink.service active, tally-filler.timer and the seat feeders listed —
# are all claims about a box that was switched. If they were true of a box that
# was NOT switched, they would be evidence of nothing: the oracle would be
# reading something other than the act it is grading.
#
# The worker box is exactly that unswitched box, by ruling and not by accident.
# ~/research-methods/DECISIONS.md D-B15: "the COORDINATOR switches under this
# run, in P05's order, after nix flake check; the WORKER box's switch stays a
# TOM LINE." So the worker holds the same `main`, declares nothing of this
# suite (the modules are coordinator-gated in three places — modules/tally-b.nix
# is imported only by hosts/coordinator, and home/tally-uplink.nix,
# home/tally-filler.nix and home/seat-feeder.nix are each `lib.mkIf
# isCoordinator`), and has never had a generation of it installed.
#
# GREEN HERE MEANS RED THERE. This script exits 0 when every unit the
# coordinator's oracle finds ACTIVE is ABSENT on the worker. A worker that
# reported them present would mean either that someone switched the box (the
# TOM LINE taken without Tom) or that the coordinator oracle's clauses are true
# of any box at all and grade nothing — and this script would exit 1 saying so.
#
# READ-ONLY, BY THE CARD'S OWN NON-GOALS ("the worker box untouched"). Every
# command below is an `is-active` / `show -p` / `list-timers` query over SSH
# with BatchMode. Nothing is started, stopped, switched, built, written or
# copied on the worker; no credential is read; llama-swap on either box is
# neither called nor restarted.
set -uo pipefail

host="${U_D19_WORKER_HOST:-worker}"
ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

fail=0
pass() { printf '[P] %s\n' "$*"; }
bad()  { printf '[F] %s\n' "$*"; fail=1; }
note() { printf '[N] %s\n' "$*"; }

rc() { timeout 60 ssh "${ssh_opts[@]}" "$host" "$1" 2>/dev/null; }

printf 'U-D19 negative control — the UNSWITCHED box (%s)\n' "$host"
printf 'run at %s from %s\n\n' "$(date -u +%FT%TZ)" "$(hostname)"

if ! rc 'true' >/dev/null; then
  bad "1 cannot reach ${host} read-only over ssh — the negative control cannot be taken, and an untaken control is not a green one"
  exit 1
fi
pass "1 reachable read-only: $(rc 'hostname') ($(rc 'readlink /run/current-system'))"

# ── 2. the system-bus unit the coordinator's switch installs ────────────────
st=$(rc 'systemctl is-active tally-kernel.service'); st="${st:-<empty>}"
frag=$(rc 'systemctl show -p FragmentPath --value tally-kernel.service')
if [ "$st" != "active" ] && [ -z "$frag" ]; then
  pass "2 tally-kernel.service ABSENT on ${host}: is-active=${st}, FragmentPath empty"
else
  bad "2 tally-kernel.service is NOT absent on ${host}: is-active=${st}, FragmentPath='${frag}' — either the box was switched or the coordinator's clause grades nothing"
fi

# ── 3. the user-bus unit ────────────────────────────────────────────────────
ust=$(rc 'systemctl --user is-active tally-uplink.service'); ust="${ust:-<empty>}"
ufrag=$(rc 'systemctl --user show -p FragmentPath --value tally-uplink.service')
if [ "$ust" != "active" ] && [ -z "$ufrag" ]; then
  pass "3 tally-uplink.service ABSENT on ${host}: is-active=${ust}, FragmentPath empty"
else
  bad "3 tally-uplink.service is NOT absent on ${host}: is-active=${ust}, FragmentPath='${ufrag}'"
fi

# ── 4. the timers the coordinator's switch arms ─────────────────────────────
timers=$(rc "systemctl --user list-timers --all --no-legend --no-pager | awk '{print \$(NF-1)}'")
found=""
for t in tally-filler.timer tally-seat-feeder-claude.timer tally-seat-feeder-codex.timer tally-seat-feeder-pi-qwencloud.timer; do
  case "$timers" in *"$t"*) found="${found}${t} ";; esac
done
if [ -z "$found" ]; then
  pass "4 none of tally-filler.timer / tally-seat-feeder-{claude,codex,pi-qwencloud}.timer is listed on ${host}"
else
  bad "4 the unswitched box lists: ${found}— it is not unswitched"
fi

# ── 5. the rewrite's chain ──────────────────────────────────────────────────
ledger=$(rc 'stat -c %s /home/tom/.local/state/tally-rewrite/ledger.jsonl 2>/dev/null')
if [ -z "$ledger" ]; then
  pass "5 ~/.local/state/tally-rewrite/ledger.jsonl absent on ${host} — no kernel ever served there"
else
  bad "5 ${host} carries a rewrite ledger of ${ledger} bytes"
fi

# ── 6. the declaration side: the worker's own config declares none of it ────
# Measured in THIS repository rather than on the box, so the control also fails
# if a future edit widened the modules off the coordinator gate.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
w=".#nixosConfigurations.worker.config"
q() { nix eval --offline --raw "$@" 2>/dev/null; }
decl_sys=$(cd "$here" && q "$w" --apply 'c: if c.systemd.services ? tally-kernel then "yes" else "no"')
decl_up=$(cd "$here" && q "$w.home-manager.users.tom" --apply 'h: if h.systemd.user.services ? tally-uplink then "yes" else "no"')
decl_fill=$(cd "$here" && q "$w.home-manager.users.tom" --apply 'h: if h.systemd.user.timers ? tally-filler then "yes" else "no"')
decl_feed=$(cd "$here" && q "$w.home-manager.users.tom" --apply 'h: if h.systemd.user.timers ? tally-seat-feeder-claude then "yes" else "no"')
if [ "$decl_sys$decl_up$decl_fill$decl_feed" = "nononono" ]; then
  pass "6 the worker's own rendered config declares none of the four (tally-kernel/tally-uplink/tally-filler/tally-seat-feeder-claude) — the absence above is by construction, not by a switch not yet taken"
else
  bad "6 the worker's config declares: kernel=${decl_sys} uplink=${decl_up} filler=${decl_fill} feeder=${decl_feed} — the coordinator gate leaked"
fi

note "the worker box's own switch stays a TOM LINE (D-B15); nothing here takes it"

if [ "$fail" = 0 ]; then
  printf '\nNEGATIVE CONTROL HELD: every unit the coordinator switch installs is ABSENT on the unswitched box.\n'
  exit 0
fi
printf '\nNEGATIVE CONTROL BROKEN.\n'
exit 1
