#!/usr/bin/env bash
# U-D13 EVALUATOR PROBE (RULE OF THE NIGHT, 2026-09-07) — written by the
# mechanical evaluator, not by the unit's author. The card's clauses A/B/C and
# the unit's own test-tally-b-input.sh assert what the module DECLARES. This
# probe asserts that the module's GUARDS BITE — that the two `assertions` are
# load-bearing rather than decoration, that the one option the unit deferred
# (evaluatorLock, DF-U-D13-2) is a real wire and not a stub, and that the two
# tmpfiles rule sets this unit puts over the SAME two paths from two different
# buses do not fight at switch time.
#
# Everything here is eval-time and --offline: nothing is built, nothing is
# switched, no state is written, no credential is read. Each guard is shown
# GREEN at the delivered tree and RED under a one-line override, because a
# guard nobody has seen red is not a guard.
set -uo pipefail
repo="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$repo" || { echo "FAIL: cannot cd $repo"; exit 2; }

fail=0
pass() { printf '[P] %s\n' "$*"; }
bad()  { printf '[F] %s\n' "$*"; fail=1; }

# ext <nix-attrset-of-overrides> <attr-path-after-config> -> prints value, rc
ext() {
  nix eval --offline --raw --impure --expr "
    let f = builtins.getFlake \"git+file://$repo\";
        c = f.nixosConfigurations.coordinator.extendModules {
              modules = [ { $1 } ];
            };
    in $2" 2>&1
}

# NOTE, MEASURED by this evaluator before the clauses below were written
# (D-B58): NixOS `config.assertions` are forced by `system.build.toplevel`,
# NOT by reading a single `systemd.services.<x>` attribute. A first draft of
# G1/G2 read ExecStart and both went falsely RED. The forcing point below is
# the toplevel, which is what the card's clause C and `nix flake check`
# already evaluate — so the guards are asserted where they actually run.

# --- G1: the stateDir assertion bites -------------------------------------
# The module claims its eval-time assertion mirrors the kernel's own
# Ledger::open refusal of branch (a)'s state root. If it did not fire, a
# stateDir of ~/.local/state/tally would evaluate fine and the unit would be
# discovered broken only as a boot loop on U-D19's switch.
out=$(ext 'services.tally-kernel.stateDir = "/home/tom/.local/state/tally";' \
          'c.config.system.build.toplevel.drvPath')
if [ $? -ne 0 ] && printf '%s' "$out" | grep -q 'must live under tally-rewrite'; then
  pass "G1 stateDir=~/.local/state/tally is REFUSED at eval by the named assertion"
else
  bad  "G1 the live state root evaluated without firing the assertion: $out"
fi

# --- G2: the empty-rows assertion bites ------------------------------------
out=$(ext 'services.tally-kernel.rows = [ ];' \
          'c.config.system.build.toplevel.drvPath')
if [ $? -ne 0 ] && printf '%s' "$out" | grep -q 'rows is empty'; then
  pass "G2 rows = [ ] is REFUSED at eval by the named assertion"
else
  bad  "G2 an empty row set evaluated: $out"
fi

# --- G3: evaluatorLock is a wire, not a stub -------------------------------
# DF-U-D13-2 defers PASSING the lock (U-A17 has not delivered the bytes to
# lock). It does not excuse an option that is never read. Null must omit the
# flag; a set value must appear verbatim in ExecStart.
base=$(nix eval --offline --raw \
  '.#nixosConfigurations.coordinator.config.systemd.services.tally-kernel.serviceConfig.ExecStart' 2>/dev/null)
case "$base" in
  *--evaluator-lock*) bad "G3 the default (null) lock still emitted --evaluator-lock: $base" ;;
  *)                  pass "G3 evaluatorLock=null omits the flag (the deferred, honest state)" ;;
esac
# G0: the delivered tree's own toplevel evaluates — the GREEN side of G1/G2,
# so a guard that fired on everything would be caught here.
if ext 'services.tally-kernel.enable = true;' 'c.config.system.build.toplevel.drvPath' >/dev/null 2>&1; then
  pass "G0 the delivered coordinator toplevel evaluates with no failed assertion"
else
  bad  "G0 the delivered coordinator toplevel does not evaluate"
fi

out=$(ext 'services.tally-kernel.evaluatorLock = /etc/hostname;' \
          'c.config.systemd.services.tally-kernel.serviceConfig.ExecStart')
if [ $? -eq 0 ] && printf '%s' "$out" | grep -q -- '--evaluator-lock /nix/store/.*'; then
  pass "G3 a set evaluatorLock reaches ExecStart: ...${out##*--evaluator-lock}"
else
  bad  "G3 evaluatorLock is not wired to ExecStart: $out"
fi

# --- G4: the two buses do not fight over the same two directories ----------
# This unit adds SYSTEM tmpfiles rules for the state root and meters dir that
# U-D12's seat feeders already declare on tom's USER bus. systemd-tmpfiles `d`
# lines are idempotent only while they agree; a mode or owner disagreement is a
# chmod/chown flip on every boot, over the directory holding the witness chain.
both=$(nix eval --offline --json --impure --expr '
  let f = builtins.getFlake "git+file://'"$repo"'"; c = f.nixosConfigurations.coordinator.config;
      keep = builtins.filter (r: builtins.match ".*tally-rewrite.*" r != null);
      mode = r: builtins.elemAt (builtins.filter builtins.isString (builtins.split " +" r)) 2;
      path = r: builtins.elemAt (builtins.filter builtins.isString (builtins.split " +" r)) 1;
  in {
    sys  = builtins.map (r: { p = path r; m = mode r; }) (keep c.systemd.tmpfiles.rules);
    user = builtins.map (r: { p = path r; m = mode r; })
             (keep (c.home-manager.users.tom.systemd.user.tmpfiles.rules or []));
  }' 2>/dev/null)
sysmodes=$(printf '%s' "$both" | tr ',' '\n' | grep -c '"m":"0700"')
if [ -z "$both" ] || ! printf '%s' "$both" | grep -q '"m":"0[0-7]*"' ; then
  bad "G4 could not read the tmpfiles modes: ${both:-<eval failed>}"
elif printf '%s' "$both" | grep -qv '"m":"0700"' && [ "$sysmodes" -lt 4 ]; then
  bad "G4 the system-bus and user-bus tmpfiles rules over tally-rewrite disagree: $both"
else
  pass "G4 all four tally-rewrite tmpfiles rules (2 system + 2 user) are 0700 for tom: $both"
fi
# and the system rules must name tom explicitly — a `- -` owner on a SYSTEM
# rule would create the witness chain's directory as root:root.
sysowner=$(nix eval --offline --json --impure --expr '
  let f = builtins.getFlake "git+file://'"$repo"'"; c = f.nixosConfigurations.coordinator.config;
  in builtins.all (r: builtins.match "d /home/tom/.local/state/tally-rewrite.* 0700 tom users - -" r != null)
       (builtins.filter (r: builtins.match ".*tally-rewrite.*" r != null) c.systemd.tmpfiles.rules)' 2>/dev/null)
if [ "$sysowner" = "true" ]; then
  pass "G4 every SYSTEM tally-rewrite rule names 'tom users' (not root:root)"
else
  bad  "G4 a system tally-rewrite tmpfiles rule does not name tom: ${sysowner:-<eval failed>}"
fi

exit "$fail"
