#!/usr/bin/env bash
# U-D19 (dotfiles#322) — THE MECHANICAL EVALUATOR'S RE-RUN OF THE DOMINANT.
#
#   bash tools/u-d19-evaluator-clause-rerun.sh [repo]
#
# WHY THIS FILE EXISTS AND IS NOT tools/u-d19-switch-oracle.sh. The card's
# oracle names an ACT — `sudo nixos-rebuild switch --flake .#coordinator` — and
# the unit's own oracle takes it. The mechanical evaluator's locks forbid it
# ("NEVER nixos-rebuild switch"), so the evaluator cannot run the author's
# script byte-exact: doing so would take a second switch. Procedure step 2 says
# to run the entry's clauses INDIVIDUALLY so a green cannot hide a clause that
# does not discriminate; this runs every clause EXCEPT B, read-only, and
# replaces B with the only honest evaluator-side form (2c: an amended clause is
# RUN before it is written down):
#
#   B' the switch WAS taken — the running generation is not the committed
#      pre-switch baseline, and /run/current-system is a different store path
#      than tools/u-d19-switch-baseline.env records.
#
# Clause A is run in its FULL form, as the card says, in the delivered worktree.
# Nothing here switches, reboots, touches the worker box (where the fleet's
# Halogen server runs) or the NAS, reads a credential, or writes
# ~/.local/state/tally/.
set -uo pipefail

repo="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
fail=0
pass() { printf '[P] %s\n' "$*"; }
bad()  { printf '[F] %s\n' "$*"; fail=1; }
note() { printf '[N] %s\n' "$*"; }

state=/home/tom/.local/state/tally-rewrite
ledger="$state/ledger.jsonl"
. "$repo/tools/u-d19-switch-baseline.env" || { echo "FAIL: no baseline"; exit 2; }

printf 'U-D19 evaluator clause re-run — repo %s, host %s\n\n' "$repo" "$(hostname)"

# A (FULL, as the card says) — run separately and its rc passed in, because it
# is minutes long and must not be re-run once per invocation of this file.
if [ -n "${U_D19_CLAUSE_A_RC:-}" ]; then
  [ "$U_D19_CLAUSE_A_RC" = 0 ] \
    && pass "A nix flake check (FULL, not --no-build) -> 0 (run separately in $repo)" \
    || bad  "A nix flake check (FULL) -> $U_D19_CLAUSE_A_RC"
else
  bad "A not run — set U_D19_CLAUSE_A_RC"
fi

# B' the switch was taken (the evaluator may not take it)
now_gen=$(readlink -f /run/current-system)
now_prof=$(basename "$(readlink /nix/var/nix/profiles/system)")
if [ "$now_gen" != "$U_D19_BEFORE_GENERATION" ] && [ "$now_prof" != "$U_D19_BEFORE_PROFILE" ]; then
  pass "B' the switch WAS taken: $now_prof ($now_gen), baseline $U_D19_BEFORE_PROFILE ($U_D19_BEFORE_GENERATION). The act itself is the author's; the evaluator's locks forbid nixos-rebuild switch."
else
  bad "B' the running generation is still the pre-switch baseline: $now_prof"
fi

# C
[ "$(systemctl is-active tally-kernel.service 2>/dev/null)" = active ] \
  && pass "C1 systemctl is-active tally-kernel.service -> active (system bus)" \
  || bad  "C1 systemctl is-active tally-kernel.service -> $(systemctl is-active tally-kernel.service 2>/dev/null), want active"
u_before=$( [ -f "$ledger" ] && stat -c %s "$ledger" || echo 0 )
systemctl --user restart tally-uplink.service >/dev/null 2>&1; u_rc=$?
u_state=$(systemctl --user is-active tally-uplink.service 2>/dev/null)
[ "$u_state" = active ] \
  && pass "C2 systemctl --user is-active tally-uplink.service -> active" \
  || { bad "C2 systemctl --user is-active tally-uplink.service -> ${u_state:-<empty>}, want active (restart rc=$u_rc)"; \
       journalctl --user -u tally-uplink.service -n 4 --no-pager 2>&1 | sed 's/^/    /'; }

# D / E4
frag_ok() { local w="$1" f="$2" r
  [ -n "$f" ] || { bad "$w FragmentPath empty"; return; }
  [ -L "$f" ] || { bad "$w '$f' is not a symlink (a plain unit file is hand-installed, Rule 9)"; return; }
  r=$(readlink -f "$f"); case "$r" in /nix/store/*) pass "$w $f -> $r";; *) bad "$w '$f' -> '${r:-<none>}', want /nix/store";; esac; }
frag_ok "D1 tally-kernel.service FragmentPath" "$(systemctl show -p FragmentPath --value tally-kernel.service 2>/dev/null)"
frag_ok "D2 tally-uplink.service FragmentPath" "$(systemctl --user show -p FragmentPath --value tally-uplink.service 2>/dev/null)"
frag_ok "E4 tally-filler.timer FragmentPath" "$(systemctl --user show -p FragmentPath --value tally-filler.timer 2>/dev/null)"

# E
timers=$(systemctl --user list-timers --all --no-legend --no-pager 2>/dev/null | awk '{print $(NF-1)}')
listed() { printf '%s\n' "$timers" | grep -qx -- "$1"; }
feeder=""
for t in $(printf '%s\n' "$timers" | grep '^tally-seat-feeder-.*\.timer$'); do
  sf=$(systemctl --user show -p FragmentPath --value "${t%.timer}.service" 2>/dev/null)
  [ -r "$sf" ] || continue
  case ",$(sed -n 's/^X-TallyRows=//p' "$sf" | head -1)," in *,cc,*) feeder="$t"; break;; esac
done
[ -n "$feeder" ] \
  && pass "E1 the timer feeding the card's cc row is listed: $feeder (there is no tally-seat-feeder-cc.timer on this estate)" \
  || bad  "E1 no listed tally-seat-feeder-*.timer declares the cc row"
for t in tally-seat-feeder-claude.timer tally-seat-feeder-codex.timer tally-seat-feeder-pi-qwencloud.timer; do
  listed "$t" && pass "E2 list-timers names $t" || bad "E2 $t is not listed"; done
listed tally-filler.timer && pass "E3 list-timers names tally-filler.timer (D-B66)" || bad "E3 tally-filler.timer is not listed"

# F — the switch installed no inference serve on this box. The fleet's one
# server is the worker's podman-halogen.service (modules/halogen.nix), and the
# coordinator carries only the utility-model client that dials it; a serve unit
# loaded on the coordinator's system bus would be a declaration this card never
# made. The worker itself is deliberately not contacted from here.
ls=$(systemctl show -p LoadState --value podman-halogen.service 2>/dev/null)
[ "$ls" = not-found ] \
  && pass "F1 podman-halogen.service is not loaded on the coordinator (LoadState=$ls): the serve is the worker's" \
  || bad  "F1 podman-halogen.service is loaded on the coordinator (LoadState='${ls:-<empty>}'); the coordinator serves nothing"
command -v utility-model >/dev/null 2>&1 \
  && pass "F2 utility-model (the client that dials the worker's Halogen server) is on PATH" \
  || bad  "F2 utility-model is not on PATH — the coordinator's one inference client is missing"

# G
u_after=$( [ -f "$ledger" ] && stat -c %s "$ledger" || echo 0 )
if [ ! -f "$ledger" ]; then bad "G1 $ledger absent"
elif [ "$u_after" -gt "$u_before" ]; then pass "G1 $ledger grew across one uplink wake: $u_before -> $u_after"
else bad "G1 $ledger did NOT grow across the wake: $u_before -> $u_after bytes"; fi

# H
sysf=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | sort | tr '\n' ' ')
usrf=$(systemctl --user --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | sort | tr '\n' ' ')
[ -z "$(printf '%s' "$sysf" | tr -d ' ')" ] && pass "H1 systemctl --failed (system) empty" || bad "H1 system --failed: $sysf"
note "H2 user --failed now: ${usrf:-<none>}; pre-switch baseline (D-B98): ${U_D19_BEFORE_USER_FAILED:-<none>}"
w=$(cd "$repo" && nix eval --offline --raw '.#nixosConfigurations.worker.config' --apply \
  'c: let h = c.home-manager.users.tom; in if (c.systemd.services ? tally-kernel) || (h.systemd.user.services ? tally-uplink) || (h.systemd.user.timers ? tally-filler) || (h.systemd.user.timers ? tally-seat-feeder-claude) then "leaked" else "clean"' 2>/dev/null)
[ "$w" = clean ] && pass "H3 the worker profile declares none of the four (D-B15)" || bad "H3 worker profile is '$w'"
[ "$(systemctl --user is-active tally-daemon.service 2>/dev/null)" = active ] \
  && pass "H4 branch (a)'s tally-daemon.service is still active" || note "H4 tally-daemon.service not active"

printf '\n'
[ "$fail" = 0 ] && { printf 'U-D19 EVALUATOR CLAUSE RE-RUN: ALL CLAUSES GREEN\n'; exit 0; }
printf 'U-D19 EVALUATOR CLAUSE RE-RUN: RED\n'; exit 1
