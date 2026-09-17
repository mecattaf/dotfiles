{
  coreutils,
  git,
  gnused,
  jq,
  lib,
  tallyLake,
  writeShellApplication,
}:
# tally-evaluator — the FIXED ARGV the kernel derives a verdict under.
#
# UNIT: the served `--evaluator-lock` (dotfiles DEFERRED.md DF-U-D13-2, the row
# this package discharges). SPEC: tally `docs/socket.md` §4 and the rewrite's
# spec §2.1 — "`verdict` payloads are derived by the kernel from the attestation
# of an `exec.run` whose `argv_sha256` matches apps/evaluator's pinned lock".
#
# WHY A WRAPPER AND NOT A PATH. The lock pins a DIGEST OF THE ARGV, computed
# over the executor's own prefix-free preimage (tally
# `crates/tally-kernel/src/exec.rs` `argv_preimage`, transcribed in
# `tools/make-evaluator-lock.sh`). An argv that carries the card, the
# deliverable or the usage source hashes differently on every evaluation and
# therefore cannot be pinned at all — which is exactly why T7-3 is a
# RULED-NEVER row of the lake's DEFERRED.md and why `tools/e2e-evaluator.sh`
# takes its whole item as ONE JSON OBJECT ON STDIN. This package is the last
# step of that discipline: it turns the two-word argv probe-C measured
# (`/bin/sh <checkout>/tools/e2e-evaluator.sh`) into ONE word that is a store
# path, so the argv the kernel hashes moves only when the pinned `tally-lake`
# input moves — never when a checkout is `git pull`ed under nobody's review.
#
# WHAT IT EXECS. `${tallyLake}/tools/e2e-evaluator.sh`, out of the flake input's
# store path, through `/bin/sh` — the same interpreter probe-C ran it under
# (MEASURED 2026-09-17: rc 0, `argv_sha256` matching the generated lock, a
# `verdict` on the chain). The script's own `#!` line is not used, so the
# interpreter is part of the wrapper's text and thus part of what the lock's
# FILE rows cannot silently change.
#
# WHAT IT DOES NOT DO. It passes no judgement, adds no flag, and reads no
# credential: the evaluator's exit code IS the verdict (spec §2.2d) and the
# kernel only records it. `"$@"` is forwarded so a hand invocation can still be
# debugged, but the LOCKED argv is the bare program name with no words after
# it — an argv with extra words hashes to something the lock does not carry and
# the kernel derives no verdict from it, which is the refusal working.
#
# THE RUNTIME CLOSURE IS THE ORACLE'S PATH. A `writeShellApplication` sets PATH
# from `runtimeInputs` alone, so what the evaluator can reach is declared here
# rather than inherited from whatever started the kernel: `jq` (the script
# parses its stdin item with it), `coreutils` (`cat`, `date`, `mkdir`, `wc`),
# `git` (apps/evaluator's deliverable checkout) and `gnused`. `node` is NOT in
# this list on purpose — the item on stdin names the interpreter by absolute
# path (`.node`), because the node the lake's own `scripts/node-env.sh` records
# is the one its packages were resolved against.
writeShellApplication {
  name = "tally-evaluator";
  runtimeInputs = [
    jq
    coreutils
    git
    gnused
  ];
  text = ''
    exec /bin/sh ${tallyLake}/tools/e2e-evaluator.sh "$@"
  '';
  meta = {
    description = "the fixed-argv mechanical evaluator the tally kernel derives a verdict under";
    mainProgram = "tally-evaluator";
    platforms = lib.platforms.linux;
  };
}
