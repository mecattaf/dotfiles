{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  findutils,
  imagemagick,
  jq,
  python3,
}:

# The paper-loop scan queue (dotfiles scanning plane, 2026-08-13). The
# Brother ADS-1800W drops page images into ~/Paper/intake; the collector
# sweeps settled files into a dated ~/Paper/jobs/<name>/ directory and
# queues one tally shell job per batch through the shared events directory
# — the same producer contract as call-diarize. The processor rotates the
# stack and transcribes handwriting through llama-swap qwen3-vl-8b-ocr.
stdenvNoCC.mkDerivation {
  pname = "paper-intake";
  version = "1.0.0";

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    install -Dm755 ${./process.py} $out/libexec/paper-intake-process.py
    install -Dm755 ${./collect.sh} $out/libexec/paper-intake-collect.sh

    makeWrapper ${lib.getExe python3} $out/bin/paper-intake \
      --add-flags $out/libexec/paper-intake-process.py \
      --prefix PATH : ${
        lib.makeBinPath [
          imagemagick
          coreutils
        ]
      }

    makeWrapper ${lib.getExe bash} $out/bin/paper-intake-collect \
      --add-flags $out/libexec/paper-intake-collect.sh \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          findutils
          jq
        ]
      }
    runHook postInstall
  '';

  meta = {
    description = "Scan-batch collector and OCR processor for the paper loop";
    mainProgram = "paper-intake";
    platforms = lib.platforms.linux;
  };
}
