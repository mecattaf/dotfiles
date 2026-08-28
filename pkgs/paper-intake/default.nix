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
# `pname` is historical and no longer describes the contents: this package
# builds exactly one binary, paper-print-flush. See git history for what the
# name used to cover.
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
