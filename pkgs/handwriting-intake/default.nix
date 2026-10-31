{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
}:
let
  python = python3.withPackages (p: [ p.pillow ]);
in
stdenvNoCC.mkDerivation {
  pname = "handwriting-intake";
  version = "0.1.0";
  src = lib.cleanSource ./.;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    export LOCAL_MODEL_ENDPOINT=${(import ../../lib/local-model.nix).endpoint}
    runHook preCheck
    PYTHONPATH=${../../lib/python}:${../handwriting-annotation}:$PWD ${python}/bin/python3 -m unittest -v test_intake test_review_integration
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/handwriting-intake" "$out/bin"
    cp intake.py README.md "$out/share/handwriting-intake/"
    makeWrapper ${python}/bin/python3 "$out/bin/handwriting-intake" \
      --add-flags "$out/share/handwriting-intake/intake.py --state /var/lib/handwriting-intake" \
      --set-default LOCAL_MODEL_ENDPOINT ${(import ../../lib/local-model.nix).endpoint}
    install -Dm644 ${../../lib/python/utility_storage.py} $out/share/handwriting-intake/utility_storage.py
    runHook postInstall
  '';
  meta = {
    description = "Manual serial Huion intake with durable receipts and writer review gates";
    mainProgram = "handwriting-intake";
    platforms = lib.platforms.linux;
  };
}
