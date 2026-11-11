{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  nodejs_24,
  llm-agents,
}:
# scheduled (AGENTS.md D52): the Scheduled CLI and the heartbeat tick.
# Cron comes from @deepseek-ai/dsh-util-time inside the same dsh store
# path the dshd release runs, so one flake.lock pin moves both. JSONC
# and the schema come from two registry tarballs, MIT, no dependencies.
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
  zod = npm "zod" "4.4.3" (
    "sha512-ytENFjIJFl2UwYglde2jchW2Hwm4GJFLDiSXWdTrJQBIN9Fcyp7n4DhxJEi"
    + "WNAJMV1/BqWfW/kkg71UDcHJyTQ=="
  );
  dshModules =
    "${llm-agents.dsh}/lib/node_modules/@deepseek-ai/dsh/node_modules";
in
stdenvNoCC.mkDerivation {
  pname = "scheduled";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    runHook preInstall
    share=$out/share/scheduled
    nm=$share/node_modules
    mkdir -p $nm/@deepseek-ai $nm/jsonc-parser $nm/zod
    cp -r src test $share/
    tar -xzf ${jsoncParser} -C $nm/jsonc-parser --strip-components=1
    tar -xzf ${zod} -C $nm/zod --strip-components=1
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
