{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
# Native memory engine only. Never run `mnemon setup`: its imperative hooks
# would modify the live Claude/Codex installations. The dedicated DSH profile
# supplies its own integration, while databases stay in ~/.mnemon on NAS.
buildGoModule rec {
  pname = "mnemon";
  version = "0.2.13";

  src = fetchFromGitHub {
    owner = "mnemon-dev";
    repo = "mnemon";
    rev = "fb3f186be865a0797ab390839cb7af6b02064708"; # v0.2.13
    hash = "sha256-fGbuzaKIBagAA9IFXCuyARmUtjaKCiAaYeR7mBPVric=";
  };
  vendorHash = "sha256-nIXIk9j3duX0wbzwc8PALs3mJq88LEalYXLWRgWqfqE=";
  subPackages = [ "." ];
  env.CGO_ENABLED = 0;
  ldflags = [
    "-s"
    "-w"
    "-X github.com/mnemon-dev/mnemon/cmd.version=${version}"
  ];

  # Do not start the Agency daemon, call a provider, or install harness hooks.
  # These upstream tests exercise the deterministic memory data plane.
  checkPhase = ''
    runHook preCheck
    export HOME="$TMPDIR/home" MNEMON_DATA_DIR="$TMPDIR/memory"
    mkdir -p "$HOME"
    go test ./internal/memory/store ./internal/memory/search ./internal/memory/graph ./internal/memory/importdraft
    runHook postCheck
  '';

  meta = {
    description = "Standalone graph memory for agents (no automatic harness setup)";
    homepage = "https://github.com/mnemon-dev/mnemon";
    license = lib.licenses.asl20;
    mainProgram = "mnemon";
  };
}
