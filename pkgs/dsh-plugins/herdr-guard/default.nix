{
  stdenvNoCC,
  nodejs,
}:
# herdr-guard: the fleet's gate in front of the dsh-herdr tools, owned here
# (./index.js, plain ESM, no dependencies, no build step). A `tools/pre-execute`
# listener decides every `_dsh_herdr_*` call; a `tools/result` listener records
# the panes this dsh process created. dsh-herdr injects the `herdrGuard`
# service it provides, so the herdr tools never load without it. The check
# phase runs ./guard.test.mjs against fake exec objects.
stdenvNoCC.mkDerivation {
  pname = "herdr-guard";
  version = "1.0.0";
  src = ./.;
  nativeBuildInputs = [ nodejs ];
  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    node --test guard.test.mjs
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm0644 -t $out index.js package.json cordis.patch.yml
    runHook postInstall
  '';
  meta.description = "dsh plugin gating the dsh-herdr tools (ids, own panes, HERDR_ENV, ask)";
}
