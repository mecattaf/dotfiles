#!/usr/bin/env bash
# U-D19 DF-SWITCH (dotfiles#322) — the DOMINANT oracle, mechanized as one argv.
#
#   bash tools/u-d19-switch-oracle.sh
#
# The card's oracle is prose naming an ACT and the probes that grade it:
#
#   nix flake check → 0 (full); sudo nixos-rebuild switch --flake .#coordinator
#   → 0; systemctl is-active tally-kernel.service tally-uplink.service → active
#   active; systemctl show -p FragmentPath tally-kernel.service under
#   /nix/store; systemctl --user list-timers names tally-seat-feeder-cc.timer
#   and tally-filler.timer; llama-swap.service still active and never restarted
#   (systemctl show -p ActiveEnterTimestamp unchanged); and, moved here from
#   U-D18 (D-B66) because only this unit switches: systemctl --user list-timers
#   names tally-filler.timer after the switch
#
# Every clause is run below with its MEASURED value printed, in P05's order:
#
#   A  nix flake check                        FULL, not --offline --no-build
#   B  sudo nixos-rebuild switch --flake .#coordinator   → 0
#   C  the two units ACTIVE, one per bus
#   D  FragmentPath under /nix/store, for both
#   E  the feeders' timers and tally-filler.timer LISTED
#   F  llama-swap still active and NEVER restarted, against a committed baseline
#   G  ~/.local/state/tally-rewrite/ledger.jsonl GROWING
#   H  the switch added no failed unit (D-B98), and the non-goals as bytes
#
# THE ORDER IS THE CARD'S AND IT IS LOad-BEARING. "after nix flake check (full,
# not --no-build)" is P05's own sequencing: the gate every other unit ran as
# `--offline --no-build` proves the tree EVALUATES; the full form BUILDS every
# check derivation, and this unit is the first in the suite to run it. A switch
# taken before that gate is a switch taken on an unbuilt closure.
#
# WHY THE TWO UNITS ARE PROBED ON DIFFERENT BUSES, and it is not a liberty with
# the card's text. `tally-kernel.service` is a SYSTEM unit (U-D13,
# modules/tally-b.nix, imported by hosts/coordinator only) and
# `tally-uplink.service` is tom's USER unit (U-D14, home/tally-uplink.nix —
# the lake ships a home-manager module and no NixOS module, its card's own
# non-goal). `systemctl is-active tally-uplink.service` on the system bus would
# print `inactive` forever for a unit that does not exist there, which is a
# false RED. Each is asked of the bus that owns it, and each bus is printed.
#
# WHY THE FEEDER TIMER IS NAMED `tally-seat-feeder-claude.timer` AND NOT
# `tally-seat-feeder-cc.timer`. The card was written before U-D12 delivered.
# U-D12's DOMINANT was "nix eval of the coordinator config shows the THREE
# timers declared", and the three are named for the INSTRUMENT, not the row:
# one Claude reader writes the `cc`, `cc2` and `cc3` rows on one tick (the
# repo's own DECISIONS.md, U-D12 line (1); D-B5 keeps cc and cc2 two pools).
# There is no `tally-seat-feeder-cc.timer` on this estate and there never was.
# So clause E does not match the string: it finds the timer whose SERVICE
# declares the `cc` row in its `X-TallyRows` key and requires THAT timer to be
# listed — which is what the card's clause means, and is strictly stronger than
# a name match, because a rename that dropped the `cc` row would still be RED.
#
# NOTHING OUTSIDE THE ACT THE CARD NAMES. The switch is `#coordinator` and
# nothing else; the worker box is never contacted by this script (its probe is
# the separate negative control, tools/u-d19-worker-negative-control.sh, which
# is read-only over ssh); the NAS is not touched; nothing is rebooted;
# llama-swap is neither called nor restarted and clause F is the assertion that
# it was not; no credential is read or printed — the lake token is named as a
# path by the unit and never opened here; and nothing writes
# ~/.local/state/tally/ or ~/.local/state/tally/meters, branch (a)'s live root.
set -uo pipefail

repo="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$repo" || { echo "FAIL: cannot cd $repo"; exit 2; }

fail=0
pass() { printf '[P] %s\n' "$*"; }
bad()  { printf '[F] %s\n' "$*"; fail=1; }
note() { printf '[N] %s\n' "$*"; }

state=/home/tom/.local/state/tally-rewrite
ledger="$state/ledger.jsonl"

# The baseline is a committed FILE, never a value this run captures: a baseline
# taken at the oracle's own start would already be after any restart a previous
# run caused. See tools/u-d19-switch-baseline.env.
baseline="$repo/tools/u-d19-switch-baseline.env"
# shellcheck source=/dev/null
. "$baseline" || { echo "FAIL: cannot read the baseline $baseline"; exit 2; }

printf 'U-D19 DF-SWITCH oracle — repo %s\n' "$repo"
printf 'HEAD %s\n' "$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo '<no git>')"
printf 'host %s, run at %s\n' "$(hostname)" "$(date -u +%FT%TZ)"
printf 'baseline %s (generation %s)\n\n' "$U_D19_BEFORE_PROFILE" "${U_D19_BEFORE_GENERATION##*/}"

# ── A. nix flake check, FULL ────────────────────────────────────────────────
# Not --offline: the full form builds check derivations whose inputs may need
# substitution, and P05 step 5 names this as "also the first networked nix run".
# Not --no-build: that is the targeted gate every OTHER unit in the suite ran,
# and running it here would make clause A a weaker claim than the card's.
a_log="$(mktemp -t u-d19-flake-check-XXXXXX.log)"
if timeout 7200 nix flake check --keep-going >"$a_log" 2>&1; then
  pass "A nix flake check (FULL, not --no-build) -> 0   log $a_log"
else
  arc=$?
  bad "A nix flake check (FULL) -> $arc; first errors below, full log $a_log"
  grep -n '^error' "$a_log" | head -5 | sed 's/^/    /'
fi

# ── B. the switch, in P05's order ───────────────────────────────────────────
# `.#coordinator` and nothing else (D-B15: the worker box's switch stays a TOM
# LINE). `sudo -n` so a box without passwordless sudo fails loudly here instead
# of hanging on a prompt no evaluator can answer.
if ! sudo -n true 2>/dev/null; then
  bad "B sudo -n is not available on this box — the switch cannot be taken non-interactively"
else
  b_log="$(mktemp -t u-d19-switch-XXXXXX.log)"
  if sudo -n nixos-rebuild switch --flake "$repo#coordinator" >"$b_log" 2>&1; then
    pass "B sudo nixos-rebuild switch --flake .#coordinator -> 0   log $b_log"
  else
    brc=$?
    bad "B sudo nixos-rebuild switch --flake .#coordinator -> $brc; log $b_log"
    tail -5 "$b_log" | sed 's/^/    /'
  fi
  note "B generation now $(readlink /run/current-system) ($(basename "$(readlink /nix/var/nix/profiles/system)"))"
fi
# Read HERE, before anything below starts a unit, because clause H2 grades what
# the SWITCH did. The uplink is a oneshot with no Install section: after the
# switch it is loaded and `inactive`, and it only enters a state at all when
# clause C2 wakes it. Taking the census after that wake would charge the switch
# with a failure the oracle itself caused, and would count one failure twice —
# C2 already grades it by name.
post_switch_sys_failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | sort | tr '\n' ' ')
post_switch_usr_failed=$(systemctl --user --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | sort | tr '\n' ' ')

# ── C. the two units, one per bus ───────────────────────────────────────────
# The kernel is a `Type = simple` system service with `wantedBy =
# multi-user.target`, so the switch itself starts it and `active` here means a
# process is serving the socket.
k_state=$(systemctl is-active tally-kernel.service 2>/dev/null || true)
if [ "$k_state" = "active" ]; then
  pass "C1 systemctl is-active tally-kernel.service -> active (system bus)"
else
  bad "C1 systemctl is-active tally-kernel.service -> ${k_state:-<empty>} (system bus), want active"
  systemctl status --no-pager -n 15 tally-kernel.service 2>&1 | sed 's/^/    /' | head -20
fi

# The uplink is a `Type = oneshot` USER service with `wakes = 1` and no Install
# section (DF-U-D14-4: the uplink holds no schedule of its own). One wake is
# taken here, and `RemainAfterExit` — the one key home/tally-uplink.nix adds to
# the lake's rendered unit, asserted by flake.nix's tally-uplink-topology — is
# what makes its RESULT survive the wake, so `active` means "the last wake
# succeeded" instead of being a race against a process that already exited.
# `restart`, not `start`: on a re-run the unit is already active and `start`
# would be a no-op, so nothing would be re-measured and clause G could not move.
u_before=$( [ -f "$ledger" ] && stat -c %s "$ledger" || echo 0 )
systemctl --user restart tally-uplink.service >/dev/null 2>&1
u_rc=$?
u_state=$(systemctl --user is-active tally-uplink.service 2>/dev/null || true)
if [ "$u_state" = "active" ]; then
  pass "C2 systemctl --user is-active tally-uplink.service -> active (user bus, after one wake; Result=$(systemctl --user show -p Result --value tally-uplink.service))"
else
  bad "C2 systemctl --user is-active tally-uplink.service -> ${u_state:-<empty>} (user bus), want active; restart rc=$u_rc"
  journalctl --user -u tally-uplink.service -n 15 --no-pager 2>&1 | sed 's/^/    /' | head -20
  # THE DIAGNOSIS, PRINTED RATHER THAN GUESSED AT. The known blocker at the
  # revs this repository pins (tally-b 26d7580, tally-lake a233c30) is a
  # cross-repo contract mismatch that no dotfiles option can close, and it is
  # asked here directly so the failure names its own cause instead of leaving a
  # reader to reconstruct it from a journal line:
  #
  #   - the uplink's probe() is an `admit` with no taskId, taken over EVERY row
  #     of its rows file, in file order (tally-lake src/uplink.mjs:88-103,
  #     src/socket.mjs:105-118);
  #   - the kernel's `admit` runs `consider()` -> `stamp_row(row)`, which looks
  #     the row up in its OWN --rows table and refuses `exec_recovery_malformed`
  #     when it is not there (tally crates/tally-kernel/src/exec.rs:1340-1350);
  #   - this estate's kernel is configured, correctly, with only the three
  #     `owner: kernel` rows, because `stamp` WRITES <meters>/<row>.json with
  #     `owner: kernel` (crates/tally-kernel/src/row.rs:154-…) and giving it the
  #     seat rows would have it overwrite the rows U-D12's feeders publish,
  #     destroying D-B5's two pools.
  #
  # So the first row of docs/rows.md — `cc`, owner tom — refuses the whole wake.
  # home/tally-uplink.nix's own comment states the contract the pinned code does
  # not keep: "the served kernel answers from its own three rows AND THE METERS
  # DIR FOR THE REST, and a probe that fails is written busy with grade UNKNOWN,
  # never as false idle". Filed as mecattaf/tally and mecattaf/tally-ts-sdk
  # issues; DEFERRED.md DF-U-D19-1. Neither head carries a fix today (MEASURED
  # 2026-09-07: tally add5dddb, tally-ts-sdk f817f86d).
  kbin=$(systemctl show -p ExecStart --value tally-kernel.service 2>/dev/null | sed -n 's/.*path=\([^ ;]*\).*/\1/p' | head -1)
  ksock="$state/kernel.sock"
  if [ -x "$kbin" ] && [ -S "$ksock" ]; then
    note "C2 diagnosis — the kernel's own answer to a probe of each kind of row:"
    for r in cc gpu-coordinator mechanical; do
      note "    admit {row:$r} -> $("$kbin" call --socket "$ksock" --verb admit --body "{\"row\":\"$r\",\"request\":{}}" 2>&1 | head -1)"
    done
    note "    kernel --rows (owner: kernel only): $(systemctl show -p ExecStart --value tally-kernel.service | sed -n 's/.*--rows \([^ ;]*\).*/\1/p' | head -1)"
    note "    uplink --rows (all nine):           $(systemctl --user show -p ExecStart --value tally-uplink.service | sed -n 's/.*--rows \([^ ;]*\).*/\1/p' | head -1)"
  fi
fi

# ── D. the fragments are the store's, on both buses ─────────────────────────
# The card names the kernel's; the uplink's and the filler timer's are asserted
# too, because a unit still answering from a hand-written file would satisfy
# clause C while proving nothing about the switch (Rule 9).
#
# "UNDER /nix/store" IS A CLAIM ABOUT WHERE THE BYTES LIVE, NOT ABOUT THE
# STRING systemd PRINTS, and on this box the two differ. MEASURED 2026-09-07,
# generation 189: NixOS installs a system unit as /etc/systemd/system/<u> and
# home-manager installs a user unit as ~/.config/systemd/user/<u>, each a
# SYMLINK into the store, and systemd reports the symlink it loaded —
#
#   systemctl show -p FragmentPath tally-kernel.service
#     -> /etc/systemd/system/tally-kernel.service
#   readlink -f that
#     -> /nix/store/…-unit-tally-kernel.service/tally-kernel.service
#
# — for EVERY declared unit on this estate, llama-swap and tally-daemon
# included. A literal `case $frag in /nix/store/*)` therefore reads FAIL for a
# unit that is store-backed, which is a false RED and not a finding. (It is
# also a live defect in home/dot_local/bin/l8-flash-probe, which does exactly
# that and so reports FAIL for four units this switch installed correctly:
# filed as dotfiles#331, DEFERRED.md DF-U-D19-3, not fixed here.)
#
# So the assertion is the two-part one the clause MEANS, and both halves are
# printed: the FragmentPath is a SYMLINK (never a plain file, which is what a
# hand-installed unit is — Rule 9) and it RESOLVES under /nix/store.
frag_ok() { # $1 = label, $2 = FragmentPath
  local what="$1" frag="$2" real
  if [ -z "$frag" ]; then bad "$what FragmentPath is empty — the unit is not loaded"; return; fi
  if [ ! -L "$frag" ]; then
    bad "$what FragmentPath '$frag' is not a symlink — a plain unit file is a hand-installed one (Rule 9)"; return
  fi
  real=$(readlink -f "$frag" 2>/dev/null)
  case "$real" in
    /nix/store/*) pass "$what FragmentPath $frag -> $real" ;;
    *)            bad  "$what FragmentPath '$frag' resolves to '${real:-<unresolvable>}', want a path under /nix/store" ;;
  esac
}
frag_ok "D1 systemctl show -p FragmentPath tally-kernel.service:" \
  "$(systemctl show -p FragmentPath --value tally-kernel.service 2>/dev/null || true)"
frag_ok "D2 systemctl --user show -p FragmentPath tally-uplink.service:" \
  "$(systemctl --user show -p FragmentPath --value tally-uplink.service 2>/dev/null || true)"

# ── E. the timers the switch armed ──────────────────────────────────────────
timers=$(systemctl --user list-timers --all --no-legend --no-pager 2>/dev/null | awk '{print $(NF-1)}')
listed() { printf '%s\n' "$timers" | grep -qx -- "$1"; }

# The feeder timer is found by the ROW it feeds, not by its name — see the
# header. `X-TallyRows` is home/seat-feeder.nix's own extension key, read the
# same way tools/feeder-fixture.sh reads it.
# `systemctl show` drops keys it does not know, so X- extension keys are NOT
# readable that way (MEASURED: `systemctl --user show -p X-TallyRows
# tally-seat-feeder-claude.service` prints nothing, while the unit file two
# symlinks away carries `X-TallyRows=cc,cc2,cc3`). It is read from the fragment,
# which is also what tools/feeder-fixture.sh does.
feeder=""
feeder_rows=""
for t in $(printf '%s\n' "$timers" | grep '^tally-seat-feeder-.*\.timer$'); do
  svc="${t%.timer}.service"
  sfrag=$(systemctl --user show -p FragmentPath --value "$svc" 2>/dev/null)
  [ -n "$sfrag" ] && [ -r "$sfrag" ] || continue
  rows=$(sed -n 's/^X-TallyRows=//p' "$sfrag" | head -1)
  case ",${rows}," in *,cc,*) feeder="$t"; feeder_rows="$rows"; break ;; esac
done
if [ -n "$feeder" ]; then
  pass "E1 systemctl --user list-timers names $feeder — the timer that feeds the card's cc row (X-TallyRows=$feeder_rows; there is no tally-seat-feeder-cc.timer on this estate, see the header)"
else
  bad "E1 no listed tally-seat-feeder-*.timer declares the cc row; listed timers: $(printf '%s' "$timers" | tr '\n' ' ')"
fi

# All three instruments, since the issue title says "the feeders' timers listed".
for t in tally-seat-feeder-claude.timer tally-seat-feeder-codex.timer tally-seat-feeder-pi-qwencloud.timer; do
  if listed "$t"; then pass "E2 systemctl --user list-timers names $t"; else bad "E2 $t is not listed"; fi
done

# D-B66's clause, moved here from U-D18 because only this unit switches.
if listed tally-filler.timer; then
  pass "E3 systemctl --user list-timers names tally-filler.timer (D-B66, moved here from U-D18) — $(systemctl --user show -p ActiveState,Unit --value tally-filler.timer 2>/dev/null | tr '\n' ' ')"
else
  bad "E3 tally-filler.timer is not listed; listed timers: $(printf '%s' "$timers" | tr '\n' ' ')"
fi
frag_ok "E4 tally-filler.timer (DF-U-D18-1's discharge condition):" \
  "$(systemctl --user show -p FragmentPath --value tally-filler.timer 2>/dev/null || true)"

# ── F. llama-swap: still active, never restarted ────────────────────────────
# The card's non-goal is "never restart llama-swap", and this is where that is
# an assertion rather than an intention. Three independent readings, because
# ActiveEnterTimestamp alone would not notice a stop-and-start inside the same
# second: the entry instant, the MainPID, and the restart counter.
ls_state=$(systemctl is-active llama-swap.service 2>/dev/null || true)
ls_enter=$(systemctl show -p ActiveEnterTimestamp --value llama-swap.service 2>/dev/null || true)
ls_pid=$(systemctl show -p MainPID --value llama-swap.service 2>/dev/null || true)
ls_nre=$(systemctl show -p NRestarts --value llama-swap.service 2>/dev/null || true)
[ "$ls_state" = "active" ] \
  && pass "F1 llama-swap.service is active" \
  || bad  "F1 llama-swap.service is ${ls_state:-<empty>}, want active"
[ "$ls_enter" = "$U_D19_LLAMA_SWAP_ACTIVE_ENTER" ] \
  && pass "F2 ActiveEnterTimestamp unchanged: $ls_enter" \
  || bad  "F2 ActiveEnterTimestamp is '$ls_enter', baseline '$U_D19_LLAMA_SWAP_ACTIVE_ENTER' — it was restarted"
[ "$ls_pid" = "$U_D19_LLAMA_SWAP_MAIN_PID" ] \
  && pass "F3 MainPID unchanged: $ls_pid (the same process, not a same-second replacement)" \
  || bad  "F3 MainPID is '$ls_pid', baseline '$U_D19_LLAMA_SWAP_MAIN_PID'"
[ "$ls_nre" = "$U_D19_LLAMA_SWAP_NRESTARTS" ] \
  && pass "F4 NRestarts unchanged: $ls_nre" \
  || bad  "F4 NRestarts is '$ls_nre', baseline '$U_D19_LLAMA_SWAP_NRESTARTS'"

# ── G. the chain is growing ─────────────────────────────────────────────────
# "Growing", not "present": a ledger that exists but never gains a row is a
# kernel that serves nothing. The wake taken in clause C2 is the traffic, and
# the two sizes bracket it.
u_after=$( [ -f "$ledger" ] && stat -c %s "$ledger" || echo 0 )
if [ ! -f "$ledger" ]; then
  bad "G1 $ledger does not exist (baseline: $U_D19_BEFORE_LEDGER_BYTES)"
elif [ "$u_after" -gt "$u_before" ]; then
  pass "G1 $ledger grew across one uplink wake: $u_before -> $u_after bytes, $(wc -l <"$ledger") rows"
else
  bad "G1 $ledger did not grow across the wake: $u_before -> $u_after bytes"
fi
if [ -f "$ledger" ]; then
  kinds=$(python3 -c 'import json,sys,collections
c=collections.Counter()
for l in open(sys.argv[1]):
    l=l.strip()
    if not l: continue
    try: c[json.loads(l).get("payload",{}).get("kind","?")]+=1
    except Exception: c["<unparsed>"]+=1
print(" ".join(f"{k}={v}" for k,v in sorted(c.items())))' "$ledger" 2>/dev/null)
  note "G2 chain payload kinds: ${kinds:-<none>}"
fi

# ── H. the switch added no failed unit, and the non-goals as bytes ──────────
# D-B98: `systemctl --user --failed` already named util-row.service BEFORE this
# switch (UTIL-01, dotfiles#329) — a pre-existing failure on branch (a)'s state
# dir that this run never touches, and `reset-failed` would only clear the
# evidence. So the clause is "the switch ADDED no failed unit", measured against
# the baseline's name, never "--failed is empty".
base_usr=$(printf '%s' "$U_D19_BEFORE_USER_FAILED" | tr ' ' '\n' | sort | tr '\n' ' ')
new_usr=""
for u in ${post_switch_usr_failed:-}; do case " $base_usr " in *" $u "*) ;; *) new_usr="$new_usr$u ";; esac; done
[ -z "$(printf '%s' "${post_switch_sys_failed:-}" | tr -d ' ')" ] \
  && pass "H1 systemctl --failed (system) is empty immediately after the switch" \
  || bad  "H1 systemctl --failed (system) immediately after the switch: $post_switch_sys_failed"
if [ -z "$new_usr" ]; then
  pass "H2 the switch added no failed user unit (immediately after it: ${post_switch_usr_failed:-<none>}; pre-existing by D-B98: ${base_usr:-<none>})"
else
  bad "H2 the switch ADDED failed user unit(s): $new_usr(pre-existing: ${base_usr:-<none>})"
fi
note "H2b for completeness, the census as this run ENDS — user: $(systemctl --user --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | sort | tr '\n' ' ' | sed 's/ $//;s/^$/<none>/'); system: $(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | sort | tr '\n' ' ' | sed 's/ $//;s/^$/<none>/')" 
# The act was `#coordinator`, and this repository's worker profile still
# declares none of it — the same eval the negative control takes, so a leak in
# the coordinator gate is RED here too and not only over ssh.
wdecl=$(nix eval --offline --raw '.#nixosConfigurations.worker.config' --apply \
  'c: let h = c.home-manager.users.tom; in
   if (c.systemd.services ? tally-kernel) || (h.systemd.user.services ? tally-uplink)
      || (h.systemd.user.timers ? tally-filler) || (h.systemd.user.timers ? tally-seat-feeder-claude)
   then "leaked" else "clean"' 2>/dev/null)
[ "$wdecl" = "clean" ] \
  && pass "H3 the worker profile declares none of the four units — the switch's blast radius is the coordinator (D-B15)" \
  || bad  "H3 the worker profile is '$wdecl' — the coordinator gate leaked"
# Branch (a)'s live estate is untouched: its daemon still runs and its state
# root was neither read nor written by anything above.
[ "$(systemctl --user is-active tally-daemon.service 2>/dev/null)" = "active" ] \
  && pass "H4 the live tally-daemon.service (branch (a)) is still active — the two estates coexist" \
  || note "H4 tally-daemon.service is $(systemctl --user is-active tally-daemon.service 2>/dev/null) (branch (a)'s live daemon; the card asserts nothing about it)"

printf '\n'
if [ "$fail" = 0 ]; then
  printf 'U-D19 ORACLE PASS — the coordinator switched in P05'"'"'s order, both units active from the store, the timers armed, llama-swap untouched, the chain growing.\n'
  printf 'Negative control (must be run too, and is the card'"'"'s mutation hint): bash tools/u-d19-worker-negative-control.sh\n'
  exit 0
fi
printf 'U-D19 ORACLE FAIL\n'
exit 1
