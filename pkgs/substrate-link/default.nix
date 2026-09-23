{
  lib,
  stdenvNoCC,
  nodejs_24,
  pnpm_10,
  esbuild,
  makeWrapper,
}:
# substrate-link as one bundled file, built from the source vendored in ./src (SYNC.md names the
# upstream sha). Formerly conwip-link.
# N2: Node 24, the line the link suite ran on (24.18.0, 24.20.0 and 22.23.1 all 43/43 on 2026-09-23); the pinned
# nixpkgs b6c98e9e has nodejs_24 = 24.20.0 (read from its all-packages.nix and v24.nix).
# The bundling step itself was run by hand in the link worktree (esbuild, one 2,030,521 B .mjs that
# starts from / with only AX_CONWIP_PROTO_PATH set, drains on SIGTERM and exits 0).
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "substrate-link";
  version = "0.1.0-unstable-2026-09-23";
  src = ./src;

  nativeBuildInputs = [
    nodejs_24
    pnpm_10.configHook
    esbuild
    makeWrapper
  ];

  pnpmDeps = pnpm_10.fetchDeps {
    inherit (finalAttrs) pname version src;
    # nix build with lib.fakeHash, then the "got:" value (MEASURED 2026-09-23).
    hash = "sha256-7i4RxnkDbAV/tVZd8P+zXbhVAi7DfnZHDHq0BjnC0M4=";
    fetcherVersion = 2;
  };

  buildPhase = ''
    runHook preBuild
    esbuild apps/link/src/main.ts --bundle --platform=node --format=esm --target=node22 \
      --outfile=dist/substrate-link.mjs \
      "--banner:js=import{createRequire as __cr}from'node:module';const require=__cr(import.meta.url);"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm444 dist/substrate-link.mjs $out/lib/substrate-link/substrate-link.mjs
    install -Dm444 apps/link/proto/ax-p1.proto $out/share/substrate-link/ax-p1.proto
    makeWrapper ${lib.getExe nodejs_24} $out/bin/substrate-link \
      --add-flags $out/lib/substrate-link/substrate-link.mjs \
      --set LINK_AX_PROTO_PATH $out/share/substrate-link/ax-p1.proto
    runHook postInstall
  '';

  meta = {
    description = "Outbound-only link from the Cloudflare Substrate floor to ax on the NAS";
    mainProgram = "substrate-link";
    platforms = lib.platforms.linux;
  };
})
