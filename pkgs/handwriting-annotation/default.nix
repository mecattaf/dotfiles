{ lib, stdenvNoCC, makeWrapper, python3 }:
let
  python = python3.withPackages (p: [ p.pillow ]);
in stdenvNoCC.mkDerivation {
  pname = "handwriting-annotation";
  version = "0.1.0";
  src = lib.cleanSource ./.;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${python}/bin/python3 -m unittest -v test_review
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/handwriting-annotation" "$out/bin"
    cp review.py index.html "$out/share/handwriting-annotation/"
    makeWrapper ${python}/bin/python3 "$out/bin/handwriting-annotation" \
      --add-flags "$out/share/handwriting-annotation/review.py"
    runHook postInstall
  '';
  meta = {
    description = "Private handwriting annotation and writer-confirmed evidence library";
    platforms = lib.platforms.linux;
    mainProgram = "handwriting-annotation";
  };
}
