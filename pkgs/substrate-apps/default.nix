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
#   puller  apps/puller  the coordinator's interpreter host: leases runs (runtime:interpreter) from the
#                        floor, runs them with the interpreter and the runners, heartbeats, completes,
#                        resumes from the run's journal after a kill. Upstream runs it through tsx's ESM
#                        loader over the workspace packages (substrate, @substrate/{api,link,interpreter,
#                        runners}), so it is installed as the whole tree with its production node_modules.
#
# One pnpm workspace, one fixed-output dependency tree (pnpmDeps) shared by every program that needs
# node_modules. The pusher needs none: its bin and src import only node: builtins and each other
# (MEASURED grep, 2026-09-23, again at fc2f8bd 2026-09-24), so it is installed as files and smoke-run in its checkPhase.
#
# Re-vendor: ./sync.sh <substrate checkout> <sha>, then refresh pnpmDeps.hash (lib.fakeHash, build,
# paste the got: value). E1: the code that wraps ax lives in dotfiles, pinned by sha, never a flake input.
let
  version = "0.1.0-unstable-2026-09-24";
  src = ./src;
  # The upstream commit ./src was taken from. Keep in step with SYNC.md (sync.sh rewrites both).
  sourceSha = "fc2f8bd5d1492343585914b4ed343d001a192f33";

  pnpmDeps = pnpm_10.fetchDeps {
    pname = "substrate-apps";
    inherit version src;
    # nix build .#substrate-apps-link with lib.fakeHash, then the "got:" value (MEASURED 2026-09-23; unchanged at
    # fc2f8bd, 2026-09-24: its lockfile only adds the apps/evaluator importer, no new packages).
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

  puller = stdenvNoCC.mkDerivation {
    pname = "substrate-puller";
    inherit version src pnpmDeps;
    nativeBuildInputs = [
      nodejs_24
      pnpm_10.configHook
      makeWrapper
    ];
    # Production dependencies only: tsx, effect, smol-toml, grpc and the workspace links. vitest,
    # typescript and fast-check stay out of the closure.
    pnpmInstallFlags = [ "--prod" ];
    dontBuild = true;
    doCheck = true;
    # Start it with no config: every import resolves through tsx and the workspace links, main() runs,
    # and it exits 78 with a `config-invalid` line ("[puller] holder is required"). Anything else, a
    # missing module above all, is a different exit.
    checkPhase = ''
      runHook preCheck
      export HOME=$PWD/home
      mkdir -p $HOME
      set +e
      log=$(node apps/puller/bin/substrate-puller.mjs 2>&1)
      rc=$?
      set -e
      printf '%s\n' "$log" | tail -n 40
      if [ "$rc" != 78 ]; then echo "expected exit 78 (config-invalid) with no config, got $rc"; exit 1; fi
      printf '%s\n' "$log" | grep -q '"config-invalid"'
      runHook postCheck
    '';
    installPhase = ''
      runHook preInstall
      rm -rf home
      mkdir -p $out/lib
      cp -a . $out/lib/substrate-apps
      makeWrapper ${lib.getExe nodejs_24} $out/bin/substrate-puller \
        --add-flags $out/lib/substrate-apps/apps/puller/bin/substrate-puller.mjs
      runHook postInstall
    '';
    passthru = { inherit sourceSha; };
    meta = {
      description = "The Substrate interpreter host: leases runs from the floor and runs them on this box's runtimes";
      mainProgram = "substrate-puller";
      platforms = lib.platforms.linux;
    };
  };
in
{
  inherit
    link
    pusher
    puller
    pnpmDeps
    sourceSha
    ;
}
