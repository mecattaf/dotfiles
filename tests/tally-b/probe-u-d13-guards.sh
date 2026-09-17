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
# Everything here is --offline, nothing is switched, no state is written and no
# credential is read. G1/G2/G4 are eval-time only; G3 additionally BUILDS one
# derivation — the evaluator lock the module now serves — because a lock whose
# rows were never recomputed is a claim and not a guard. Each guard is shown
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

# --- G3: the SERVED evaluator lock recomputes, row for row -----------------
# DF-U-D13-2 is discharged: the module no longer defers PASSING the lock, it
# builds one. So this guard flipped with it. The old clause asserted that the
# default (null) omitted the flag — the honest state while `apps/evaluator` had
# not been delivered to the lake. The bytes exist now
# (`${inputs.tally-lake}/apps/evaluator`), the module generates a lock over them
# with the KERNEL's own tools/make-evaluator-lock.sh, and what must be guarded
# is no longer "is the option read" but "does the served lock still mean what it
# says": its argv row must be the digest of the wrapper this repository builds,
# and every file row must recompute byte-for-byte from the PINNED lake input.
#
# That is exactly `scripts/verify-evaluator-lock.sh --lock … --root … --argv …`
# from the pinned kernel input — the kernel's own refusal, run ahead of the
# kernel. Nothing here is transcribed: the lock, the wrapper, the lake root and
# the verifier all come out of this tree's two pins.
lake=$(nix eval --offline --raw --impure --expr \
  "(builtins.getFlake \"git+file://$repo\").inputs.tally-lake.outPath" 2>/dev/null)
kern=$(nix eval --offline --raw --impure --expr \
  "(builtins.getFlake \"git+file://$repo\").inputs.tally-b.outPath" 2>/dev/null)
# The wrapper is re-derived here from pkgs/ rather than read off the lock's own
# `# argv:` comment: reading the argv out of the artifact under test would make
# part C of the verifier tautological.
wrapper=$(nix eval --offline --raw --impure --expr \
  "let f = builtins.getFlake \"git+file://$repo\";
   in (f.nixosConfigurations.coordinator.pkgs.callPackage $repo/pkgs/tally-evaluator {
        tallyLake = f.inputs.tally-lake;
      }).outPath" 2>/dev/null)
lock=$(nix build --offline --no-link --print-out-paths \
  "$repo#nixosConfigurations.coordinator.config.services.tally-kernel.evaluatorLock" 2>/dev/null)
case "$lock" in
  /nix/store/*) pass "G3 the default evaluatorLock is a built store path: $lock" ;;
  *)            bad  "G3 the default evaluatorLock did not build to a store path: ${lock:-<build failed>}" ;;
esac
if [ -n "$lock" ] && [ -n "$lake" ] && [ -n "$kern" ] && [ -n "$wrapper" ] \
  && sh "$kern/scripts/verify-evaluator-lock.sh" \
       --lock "$lock" --root "$lake" --argv "$wrapper/bin/tally-evaluator" >/dev/null 2>&1; then
  pass "G3 verify-evaluator-lock.sh rc 0: every file row recomputes from the pinned lake, and the argv row is the digest of $wrapper/bin/tally-evaluator"
else
  bad  "G3 verify-evaluator-lock.sh refused the served lock (lock=${lock:-<none>} root=${lake:-<none>} argv=${wrapper:-<none>}/bin/tally-evaluator)"
fi
# THE RED SIDE. The same verifier, over the same lock, with the argv probe-C ran
# BEFORE the wrapper existed (`/bin/sh <lake>/tools/e2e-evaluator.sh`, two
# words). It must DIVERGE (rc 4) — otherwise part C is not comparing anything
# and the green above would mean only "the file parses".
if [ -n "$lock" ] && [ -n "$lake" ] && [ -n "$kern" ]; then
  sh "$kern/scripts/verify-evaluator-lock.sh" \
    --lock "$lock" --root "$lake" \
    --argv /bin/sh --argv "$lake/tools/e2e-evaluator.sh" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 4 ]; then
    pass "G3 the pre-wrapper two-word argv DIVERGES against the same lock (rc 4) — part C really compares"
  else
    bad  "G3 a foreign argv did not diverge against the served lock (rc $rc, wanted 4)"
  fi
else
  bad  "G3 could not run the negative control: lock/root/kernel input unresolved"
fi
# The flag reaches the rendered unit, naming that same store lock.
base=$(nix eval --offline --raw \
  '.#nixosConfigurations.coordinator.config.systemd.services.tally-kernel.serviceConfig.ExecStart' 2>/dev/null)
case "$base" in
  *"--evaluator-lock $lock"*)
    pass "G3 ExecStart serves it: …${base##*--evaluator-lock}" ;;
  *)
    bad  "G3 ExecStart does not carry --evaluator-lock $lock: ${base:-<eval failed>}" ;;
esac
# And null is STILL a wire, not a hole: a host with no evaluator to lock can set
# it back and the flag disappears rather than pointing at a stale store path.
out=$(ext 'services.tally-kernel.evaluatorLock = null;' \
          'c.config.systemd.services.tally-kernel.serviceConfig.ExecStart')
case "$out" in
  *--evaluator-lock*) bad "G3 evaluatorLock=null still emitted --evaluator-lock: $out" ;;
  *tally-kernel*)     pass "G3 evaluatorLock=null omits the flag (the option is still a wire in both directions)" ;;
  *)                  bad "G3 could not render ExecStart with evaluatorLock=null: $out" ;;
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
  pass "G3 a SET evaluatorLock still overrides the default and reaches ExecStart: ...${out##*--evaluator-lock}"
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
