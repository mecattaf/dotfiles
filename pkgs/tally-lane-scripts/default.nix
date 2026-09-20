{
  lib,
  stdenvNoCC,
  bash,
  python3,
}:
# tally-lane-scripts (2026-09-20 corrections), the three programs three user
# units used to reach through a HOME path, carried by this repository instead.
#
# WHY THIS PACKAGE EXISTS. Until today home/tally-filler.nix, home/seat-feeder.nix
# and home/tally-pump.nix named their verbs as `%h/research-methods/...` and
# `%h/sept7/plan/codex-lane/pump.sh`. Both of those trees move in the 2026-09-20
# home migration (the register to ~/mecattaf/research-methods, ~/sept7 removed
# after its working copy was landed in notes), so a unit that names the SCRIPT by
# a home path breaks at the next switch. The scripts are small and stable, so the
# repository carries them and the units name a store path.
#
# WHAT THIS PACKAGE IS NOT. It is not the register, and it does not make the
# register a flake input (DECISIONS.md D-B12, "the register stays local"). Only
# the three ENTRY POINTS live here. Their DATA roots stay out of store and are
# passed in by the units:
#   e1-loop.sh       E1_REGISTER_ROOT  (tools/e1-rungs.py, tools/gpu-lease.sh,
#                                       tools/run-e1-worker.sh, tools/check-e1.sh,
#                                       bin/register, cards/, receipts/)
#   pump.sh          LANE_DIR, PUMP_RECEIPTS_DIR (next.py, harvest.py, seat.py,
#                                       repair.py, merge-reconcile.py,
#                                       codex-window.py, results.json, runs/, evals/)
#   stamp-receipt.py no register dependency at all (stdlib, reads ~/.claude*/ and
#                                       ~/.codex/ through $HOME)
# Those residuals are listed in the PR that introduced this package.
#
# The two shell programs keep their exact upstream bytes apart from the one
# marked "2026-09-20 corrections" line each that makes the data root overridable;
# stamp-receipt.py is byte-identical to the register's copy.
stdenvNoCC.mkDerivation {
  pname = "tally-lane-scripts";
  version = "2026-09-20";
  src = ./.;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    substitute e1-loop.sh "$out/bin/e1-loop.sh" \
      --replace-fail '#!/usr/bin/env bash' '#!${bash}/bin/bash'
    substitute pump.sh "$out/bin/pump.sh" \
      --replace-fail '#!/usr/bin/env bash' '#!${bash}/bin/bash'
    substitute stamp-receipt.py "$out/bin/stamp-receipt.py" \
      --replace-fail '#!/usr/bin/env python3' '#!${python3.interpreter}'
    chmod +x "$out/bin/e1-loop.sh" "$out/bin/pump.sh" "$out/bin/stamp-receipt.py"
    runHook postInstall
  '';
  meta = {
    description = "The filler lane, seat feeder and release station entry points, carried in-repo instead of under a home path";
    license = lib.licenses.unfree;
    platforms = lib.platforms.linux;
  };
}
