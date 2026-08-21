{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  cups,
  jq,
}:

# Print-outbox flusher for the paper loop's quiet hours (home/paper.nix).
# The package keeps its historical name: it used to also carry the Brother
# ADS-1800W scan collector + OCR processor, removed 2026-08-20 when the
# scanner was returned (see git history for collect.sh / process.py).
stdenvNoCC.mkDerivation {
  pname = "paper-intake";
  version = "1.1.0";

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    install -Dm755 ${./flush.sh} $out/libexec/paper-print-flush.sh

    makeWrapper ${lib.getExe bash} $out/bin/paper-print-flush \
      --add-flags $out/libexec/paper-print-flush.sh \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          cups
          jq
        ]
      }
    runHook postInstall
  '';

  meta = {
    description = "Quiet-hours print outbox flusher for the paper loop";
    mainProgram = "paper-print-flush";
    platforms = lib.platforms.linux;
  };
}
