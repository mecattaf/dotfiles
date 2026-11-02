{ lib, stdenvNoCC, makeWrapper, python3, quickshell, tacit-kit }:
stdenvNoCC.mkDerivation {
  pname = "tacit-kit-trial";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  installPhase = ''
    mkdir -p $out/share/tacit-kit-trial
    cp server.py index.html $out/share/tacit-kit-trial/
    cp -r qml $out/share/tacit-kit-trial/
    makeWrapper ${python3}/bin/python3 $out/bin/tacit-kit-trial \
      --add-flags $out/share/tacit-kit-trial/server.py \
      --set TACIT_QS ${quickshell}/bin/qs \
      --set TACIT_KIT ${tacit-kit}/share/tacit-kit
    # A standalone launcher also makes arbitrary Tacit apps easy to try.
    makeWrapper ${quickshell}/bin/qs $out/bin/tacit-qs \
      --prefix QML_IMPORT_PATH : ${tacit-kit}/share/tacit-kit/qml
  '';
  meta = {
    description = "Localhost walkthrough controlling real Tacit Kit windows";
    platforms = lib.platforms.linux;
    mainProgram = "tacit-kit-trial";
  };
}
