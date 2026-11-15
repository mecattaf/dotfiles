{
  lib,
  stdenvNoCC,
  nodejs,
  llm-agents,
}:
let
  peers = "${llm-agents.dsh}/lib/node_modules/@deepseek-ai/dsh/node_modules";
in
stdenvNoCC.mkDerivation {
  pname = "dsh-openrouter-free";
  version = "1.0.0";
  src = lib.cleanSourceWith {
    src = ./.;
    filter = path: _: baseNameOf path != "node_modules";
  };
  nativeBuildInputs = [ nodejs ];
  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    ln -s ${peers} node_modules
    node --test adapter.test.mjs
  '';
  installPhase = ''
    mkdir -p "$out"
    cp index.mjs package.json README.md "$out/"
    ln -s ${peers} "$out/node_modules"
  '';
  meta = {
    description = "Native DSH pi-ai OpenRouter adapter enforcing explicit free selectors and zero price caps";
    license = lib.licenses.mit;
  };
}
