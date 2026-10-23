{
  stdenvNoCC,
  nodejs,
}:
# stderr-log: the `herdr` profile's log sink, owned here (./index.js, plain
# ESM, no dependencies, no build step). dsh 0.2.1 prints no ctx.logger
# message, so without it jevcore's `[jevcore] ready · provider=mock` line and
# every plugin warning are lost. It prints error, info and warn, never debug.
# The check phase runs ./log.test.mjs against a fake logger.
stdenvNoCC.mkDerivation {
  pname = "stderr-log";
  version = "1.0.0";
  src = ./.;
  nativeBuildInputs = [ nodejs ];
  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    node --test log.test.mjs
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm0644 -t $out index.js package.json cordis.patch.yml
    runHook postInstall
  '';
  meta.description = "dsh plugin printing ctx.logger error, info and warn messages to stderr";
}
