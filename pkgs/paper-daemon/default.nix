{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  cups,
  poppler-utils,
  coreutils,
}:

# paper-daemon (dotfiles#384): the print loop owned end to end. An agent drops
# ~/Paper/intake/<slug>.md; this renders, validates, holds for quiet hours,
# checks the queue is the pinned driverless one, submits, and writes a receipt
# only when the PRINTER (not cupsd) reports the job completed with every
# impression. Units: home/paper.nix. Replaces pkgs/paper-intake, whose one
# binary (paper-print-flush) trusted lp's exit code.
#
# The renderer is the print skill's own scripts, copied into this closure so a
# deployed daemon renders with the generation it was built from, not with
# whatever the live ~/.claude/skills checkout holds at 06:05.
#
# PATH is PREFIXED, not replaced: Chrome (google-chrome-stable, the user's
# Home Manager profile), utility-model (system) and sudo (/run/wrappers) come
# from the user manager's inherited PATH, exactly as they do for an agent.
stdenvNoCC.mkDerivation {
  pname = "paper-daemon";
  version = "1.0.0";

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    share=$out/share/paper-daemon
    install -Dm644 ${./paper-daemon.py} $share/paper-daemon.py
    install -Dm644 ${./get-jobs.test} $share/get-jobs.test
    install -Dm644 ${./printer-state.test} $share/printer-state.test
    install -Dm644 ${../../home/dot_claude/skills/print/scripts/print-auto.py} $share/scripts/print-auto.py
    install -Dm644 ${../../home/dot_claude/skills/print/scripts/print-paper.py} $share/scripts/print-paper.py

    makeWrapper ${lib.getExe python3} $out/bin/paper-daemon \
      --add-flags $share/paper-daemon.py \
      --set PAPER_PRINT_AUTO $share/scripts/print-auto.py \
      --set PAPER_JOBS_TEST $share/get-jobs.test \
      --set PAPER_PRINTER_TEST $share/printer-state.test \
      --set PYTHONDONTWRITEBYTECODE 1 \
      --prefix PATH : ${
        lib.makeBinPath [
          cups
          poppler-utils
          coreutils
        ]
      }
    runHook postInstall
  '';

  meta = {
    description = "Drop-folder print daemon: render, validate, submit, receipt from the printer";
    mainProgram = "paper-daemon";
    platforms = lib.platforms.linux;
  };
}
