{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  typescript,
  nodejs,
  dshTools,
}:
# @dsh-external/dsh-herdr-toolkit: Herdr workspaces, panes and agents as dsh
# tools, behind ./tom.patch (see its header) and the herdr-guard plugin. It
# runs only in the hand-run `herdr` profile (../../dsh/default.nix), never in
# the stock headless profile substrate drives.
#
# Upstream commits lib/, which is byte-identical to a plain transpile of src/;
# this rebuilds lib/ from the patched src/ the same way, transpile-only, so no
# dsh checkout or pnpm install is needed. Its only runtime import is
# @deepseek-ai/dsh-tools, an optional peer the running dsh supplies.
#
# The check phase runs upstream's node tests (as patched) against the real
# dsh-tools of the dsh this fleet runs: argv, runtime, the preview gate and the
# 23-tool registration. None of them starts herdr.
stdenvNoCC.mkDerivation {
  pname = "dsh-herdr-toolkit";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "wenhao4126";
    repo = "dsh-herdr";
    rev = "3cbea69cb89477a3ae0f9fb93d92d38618df4eab"; # tag v0.4.0
    hash = "sha256-aVS0NxTf01SRSpJQ5Z8nklY67/GmibKzrp2Z8b3jmLY=";
  };

  patches = [ ./tom.patch ];

  nativeBuildInputs = [
    typescript
    nodejs
  ];

  buildPhase = ''
    runHook preBuild
    rm -rf lib
    tsc --noCheck --noResolve --target ES2023 --module NodeNext \
      --moduleResolution NodeNext --rootDir src --outDir lib src/*.ts
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    mkdir -p node_modules/@deepseek-ai
    ln -s ${dshTools} node_modules/@deepseek-ai/dsh-tools
    node --test test/*.test.mjs
    rm -rf node_modules
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r lib package.json cordis.patch.yml LICENSE README.md $out/
    runHook postInstall
  '';

  meta = {
    description = "dsh tools over the herdr CLI, patched for the fleet (no send-text, env or native args)";
    homepage = "https://github.com/wenhao4126/dsh-herdr";
    license = lib.licenses.bsd3;
  };
}
