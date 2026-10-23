{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  typescript,
  jq,
}:
# jevcore-dsh 0.4.2 (PerryLink/jevcore): TypeSafe Jev as a dsh service plus
# three tools (jev_ask, jev_rank, jev_check) and a skill. Mounted only in the
# hand-run `herdr` profile, on its offline mock provider (the profile row in
# ../../dsh/config.nix). On the mock every answer is SYNTHETIC hash noise; it
# is here so the plugin path is proven before a real Jev route exists.
#
# Built from git: npm's jevcore-dsh 0.4.1 declares engines.dsh <0.2.0, and
# 0.4.2 (which admits 0.2.x) was never published. Transpile-only, core first,
# then the plugin: core has no runtime dependency but the optional
# @typesafe-ai/sdk, and the plugin's only other imports are the dsh peers the
# running dsh supplies. So there is no pnpm dependency fetch at all.
#
# @typesafe-ai/sdk is left out on purpose. Its dynamic import is jevcore's only
# network path, so `provider: live` or `openrouter` fails provider-unavailable
# instead of sending session content anywhere.
#
# ./inject.patch: `inject` is tools only, and the credentials service is
# looked up optionally (as upstream already does for skills). Headless
# disables `credentials`, so the upstream inject would leave the row pending
# forever; re-enabling `credentials` in the profile instead would change the
# Qwen key's lookup order there.
let
  version = "0.4.2";
  tsc = dir: ''
    (cd ${dir} && tsc --noCheck --noResolve --target ES2023 --module NodeNext \
      --moduleResolution NodeNext --verbatimModuleSyntax --rootDir src --outDir lib \
      $(find src -name '*.ts' ! -name '*.d.ts'))
  '';
in
stdenvNoCC.mkDerivation {
  pname = "jevcore-dsh";
  inherit version;

  src = fetchFromGitHub {
    owner = "PerryLink";
    repo = "jevcore";
    rev = "ce3f5c57b61e05ba6b5aaecc7c571e41aa5d788d";
    hash = "sha256-wuz1ejUwn84LPrbND5ZmTVtOR9qy1JsyZ6KWgDlwbbo=";
  };

  patches = [ ./inject.patch ];

  nativeBuildInputs = [
    typescript
    jq
  ];

  buildPhase = ''
    runHook preBuild
    ${tsc "packages/core"}
    ${tsc "packages/dsh"}
    runHook postBuild
  '';

  # The plugin package, with core beside it in its own node_modules. The
  # workspace link becomes the exact version; core keeps its manifest but not
  # the SDK it lists as optional.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/node_modules/jevcore
    cd packages/dsh
    jq '.dependencies.jevcore = "${version}"' package.json > $out/package.json
    cp -r lib skills cordis.patch.yml LICENSE NOTICE $out/
    cp -r ../core/package.json ../core/lib ../core/LICENSE ../core/NOTICE $out/node_modules/jevcore/
    runHook postInstall
  '';

  meta = {
    description = "TypeSafe Jev for dsh (jevcore-dsh), built offline-only: no TypeSafe SDK in the closure";
    homepage = "https://github.com/PerryLink/jevcore";
    license = lib.licenses.asl20;
  };
}
