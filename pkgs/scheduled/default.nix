{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  nodejs_24,
  llm-agents,
}:
# scheduled (AGENTS.md D52): the Scheduled CLI and the heartbeat tick.
# The tick links one occurrence record per due item into the superagent's
# inbox and wakes the floor; it holds no superagent logic (docs/scheduled.md).
# Cron comes from @deepseek-ai/dsh-util-time inside the same dsh store
# path the dshd release runs, so one flake.lock pin moves both. JSONC
# comes from one registry tarball, MIT, no dependencies.
let
  npm =
    name: version: hash:
    fetchurl {
      url = "https://registry.npmjs.org/${name}/-/${name}-${version}.tgz";
      inherit hash;
    };
  jsoncParser = npm "jsonc-parser" "3.3.1" (
    "sha512-HUgH65KyejrUFPvHFPbqOY0rsFip3Bo5wb4ngvdi1EpCYWUQDC5V+Y7mZws"
    + "+DLkr4M//zQJoanu1SP+87Dv1oQ=="
  );
  dshModules =
    "${llm-agents.dsh}/lib/node_modules/@deepseek-ai/dsh/node_modules";
in
stdenvNoCC.mkDerivation {
  pname = "scheduled";
  version = "0.2.0";
  src = ./.;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    runHook preInstall
    share=$out/share/scheduled
    nm=$share/node_modules
    mkdir -p $nm/@deepseek-ai $nm/jsonc-parser
    cp -r src test $share/
    tar -xzf ${jsoncParser} -C $nm/jsonc-parser --strip-components=1
    # Linked, not copied: Node resolves the real path, so dsh-util-time
    # finds its own Temporal polyfill and rrule beside it in dsh's tree.
    ln -s ${dshModules}/@deepseek-ai/dsh-util-time \
      $nm/@deepseek-ai/dsh-util-time
    makeWrapper ${lib.getExe nodejs_24} $out/bin/scheduled \
      --add-flags $share/src/cli.mjs
    runHook postInstall
  '';
  passthru.node = nodejs_24;
  meta.mainProgram = "scheduled";
}
