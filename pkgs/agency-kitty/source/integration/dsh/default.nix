{ lib, stdenvNoCC, nodejs, agency-kitty }:
stdenvNoCC.mkDerivation {
  pname = "agency-kitty-dsh";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ nodejs ];
  dontBuild = true;
  postPatch = ''
    substituteInPlace cordis.patch.yml \
      --replace-fail '@AGENCY_KITTY_COMMAND@' '${agency-kitty}/bin/agency-kitty'
  '';
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    node --test test.mjs
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out index.mjs package.json cordis.patch.yml README.md
    runHook postInstall
  '';
  meta = {
    description = "Read-only native Kitty catalogue for an existing DSH Host";
    license = lib.licenses.mit;
  };
}
