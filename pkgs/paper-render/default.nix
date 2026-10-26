{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  chromium,
  fontconfig,
  makeFontsConf,
  eb-garamond,
  libre-baskerville,
  source-serif,
  liberation_ttf,
  dejavu_fonts,
  poppler-utils,
  writeShellApplication,
}:
let
  localModel = import ../../lib/local-model.nix;
  utility = writeShellApplication {
    name = "utility-model";
    runtimeInputs = [ python3 ];
    text = ''
      exec ${lib.getExe python3} ${../utility-model/utility_model.py} "$@" \
        --endpoint ${lib.escapeShellArg localModel.endpoint} \
        --concrete-model ${lib.escapeShellArg localModel.modelId} --context-tokens 102400
    '';
  };
  fonts = makeFontsConf {
    fontDirectories = [ eb-garamond libre-baskerville source-serif liberation_ttf dejavu_fonts ];
  };
in
stdenvNoCC.mkDerivation {
  pname = "paper-render";
  version = "1.0.0";
  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    runHook preInstall
    share=$out/share/paper-render
    install -Dm644 ${../paper-daemon/render-remote.py} $share/render-remote.py
    install -Dm644 ${../../home/dot_claude/skills/print/scripts/print-auto.py} $share/scripts/print-auto.py
    install -Dm644 ${../../home/dot_claude/skills/print/scripts/print-paper.py} $share/scripts/print-paper.py
    makeWrapper ${lib.getExe python3} $out/bin/paper-render \
      --add-flags "$share/render-remote.py --worker" \
      --set PAPER_PRINT_AUTO $share/scripts/print-auto.py \
      --set FONTCONFIG_FILE ${fonts} \
      --set PYTHONDONTWRITEBYTECODE 1 \
      --prefix PATH : ${lib.makeBinPath [ chromium fontconfig poppler-utils utility ]}
    runHook postInstall
  '';
  meta = {
    description = "Compute-only print renderer with an explicit browser, fonts and Gufo utility seam";
    mainProgram = "paper-render";
    platforms = lib.platforms.linux;
  };
}
