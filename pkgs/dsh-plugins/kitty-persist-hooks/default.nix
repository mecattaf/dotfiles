{
  lib,
  stdenvNoCC,
  nodejs,
  writeText,
  # The kitty-persist program (its `hook` command). null until the flake input
  # exposes the package: the bundle row then names the bare `kitty-persist`,
  # found on the PATH of the dsh process.
  kitty-persist ? null,
}:
# kitty-persist-hooks: the dsh half of the kitty-persist harness definitions,
# owned here (./index.js, plain ESM, no dependencies, no build step). It spawns
# `kitty-persist hook dsh-<profile> EVENT` directly from the dsh process, with
# a minimal environment, for a hand-run profile's top-level agent. Selected per
# profile through programs.dsh.plugins (home/kitty-persist-agents.nix); never
# in the stock headless, sdk or acp profiles. The check phase runs
# ./hooks.test.mjs: a fake context, a fake spawn, a real stub program, and the
# event replay through the generated `dsh-herdr` definition.
let
  definitions = import ./definitions.nix { inherit lib; };
  command = if kitty-persist == null then "kitty-persist" else lib.getExe' kitty-persist "kitty-persist";
  herdrDefinition = writeText "dsh-herdr.json" (builtins.toJSON (definitions.definition "herdr"));
in
stdenvNoCC.mkDerivation {
  pname = "kitty-persist-hooks";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ nodejs ];
  dontBuild = true;
  postPatch = ''
    substituteInPlace cordis.patch.yml \
      --replace-fail '@KITTY_PERSIST_COMMAND@' ${lib.escapeShellArg command}
  '';
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    KP_DSH_DEFINITION=${herdrDefinition} node --test hooks.test.mjs
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm0644 -t $out index.js package.json cordis.patch.yml
    runHook postInstall
  '';
  passthru = {
    inherit definitions command;
  };
  meta.description = "dsh plugin reporting a hand-run agent's state to kitty-persist";
}
