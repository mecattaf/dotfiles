{
  lib,
  stdenvNoCC,
  nodejs_24,
  pnpm_10,
  esbuild,
  makeWrapper,
}:
# substrate-apps: the box-side programs of the Cloudflare Substrate (agency-agency/substrate),
# vendored in ./src at the sha SYNC.md names and built here as one package set:
#
#   link    apps/link    the NAS side: leases AgentJobs from the floor over /rpc and runs each as one
#                        ax Task. Bundled with esbuild exactly as pkgs/substrate-link does (that older
#                        copy, a021003, stays the NAS module's default until hosts/nas is re-pointed).
#   pusher  apps/pusher  the coordinator's gentle capacity pusher: `seats --json --no-spend` under the
#                        refresh policy, converted to seat-capacity/2 and posted to the floor.
#   puller  apps/puller  PENDING: not in the source tree at the pinned sha (SYNC.md). The module
#                        services.substrate.puller takes it as an option and refuses to arm without it.
#
# One pnpm workspace, one fixed-output dependency tree (pnpmDeps) shared by every program that needs
# node_modules. The pusher needs none: its bin and src import only node: builtins and each other
# (MEASURED grep, 2026-09-23), so it is installed as files and smoke-run in its checkPhase.
#
# Re-vendor: ./sync.sh <substrate checkout> <sha>, then refresh pnpmDeps.hash (lib.fakeHash, build,
# paste the got: value). E1: the code that wraps ax lives in dotfiles, pinned by sha, never a flake input.
let
  version = "0.1.0-unstable-2026-09-23";
  src = ./src;
  # The upstream commit ./src was taken from. Keep in step with SYNC.md.
  sourceSha = "dc7cd1d05b1e3938dace9d3d3cddc1a22d98d6cc";

  pnpmDeps = pnpm_10.fetchDeps {
    pname = "substrate-apps";
    inherit version src;
    # nix build .#substrate-apps-link with lib.fakeHash, then the "got:" value (MEASURED 2026-09-23).
    hash = "sha256-/10ykNk5FGChNhjBxfP8lfrUJI4G5O4kE+phfewLODc=";
    fetcherVersion = 3;
  };

  link = stdenvNoCC.mkDerivation {
    pname = "substrate-link";
    inherit version src pnpmDeps;
    nativeBuildInputs = [
      nodejs_24
      pnpm_10.configHook
      esbuild
      makeWrapper
    ];
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
    passthru = { inherit sourceSha; };
    meta = {
      description = "Outbound-only link from the Cloudflare Substrate floor to ax on the NAS";
      mainProgram = "substrate-link";
      platforms = lib.platforms.linux;
    };
  };

  pusher = stdenvNoCC.mkDerivation {
    pname = "substrate-pusher";
    inherit version src;
    nativeBuildInputs = [
      nodejs_24
      makeWrapper
    ];
    dontBuild = true;
    doCheck = true;
    # One dry tick against the vendored seat-capacity/1 fixture: reads, converts, prints, posts nothing.
    # HOME and every state path point into the build directory, so nothing outside the sandbox is touched.
    checkPhase = ''
      runHook preCheck
      export HOME=$PWD/home
      mkdir -p $HOME
      node --check apps/pusher/bin/substrate-pusher.mjs
      node apps/pusher/bin/substrate-pusher.mjs --dry-run --once \
        --seats-json apps/pusher/test/fixtures/seats-v1.json \
        --pidfile $PWD/pusher.pid --state $PWD/state.json --demand-dir $PWD/demand > tick.jsonl
      grep -q '"event"' tick.jsonl
      if grep -q '"read-failed"' tick.jsonl; then echo "the dry tick failed to read the fixture"; cat tick.jsonl; exit 1; fi
      test ! -e $PWD/pusher.pid
      runHook postCheck
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/substrate-pusher
      cp -r apps/pusher/bin apps/pusher/src apps/pusher/package.json $out/lib/substrate-pusher/
      chmod -R a-w $out/lib/substrate-pusher
      makeWrapper ${lib.getExe nodejs_24} $out/bin/substrate-pusher \
        --add-flags $out/lib/substrate-pusher/bin/substrate-pusher.mjs
      runHook postInstall
    '';
    passthru = { inherit sourceSha; };
    meta = {
      description = "The gentle capacity pusher: seats --json to the Substrate floor's POST /capacity/snapshots";
      mainProgram = "substrate-pusher";
      platforms = lib.platforms.linux;
    };
  };
in
{
  inherit
    link
    pusher
    pnpmDeps
    sourceSha
    ;
  # puller: absent at ${sourceSha}; added by the next sync once apps/puller lands upstream.
}
