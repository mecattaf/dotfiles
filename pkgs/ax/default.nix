{
  lib,
  buildGoModule,
  fetchFromGitHub,
  git,
  # The Go toolchain, passed in by overlays/default.nix rather than taken from
  # this pkgs fixpoint. See the `go` binding below for why.
  go_1_27,
}:
# google/ax — a Kubernetes control plane for agent Tasks, which delegates the
# sandbox to Agent Substrate rather than running workloads itself. Four commands
# ship in cmd/: `ax` (CLI), `ax-controller`, `ax-server`, `ax-task-runner`.
#
# NOT in nixpkgs, in any channel, under any name (checked 2026-09-22): upstream
# tagged v0.3.0 and has no nix packaging of its own, no flake, and no container
# publishing path a fleet could consume. This expression is the whole of it.
#
# Pinned by commit, not by tag, so a retag upstream cannot move what this fleet
# builds. d8ed0fe38bceb7842d3c47817d53d16ccdfcb601 IS tag v0.3.0 as of 2026-09-22.
#
# NO CARRIED PATCHES: stock v0.3.0, see the `patches` entry below. The vendored
# Substrate client stays at 672533541dbf.
let
  # go.mod's first directive is `go 1.27.1` (MEASURED). Go refuses to build a
  # module whose `go` line is newer than the running toolchain, and the sandbox
  # has no network to fetch one, so the toolchain must be at least 1.27.1:
  #   this flake's main nixpkgs pin   go = 1.26.5, go_1_27 = 1.27rc2   too old
  #   nixpkgs-fresh (flake.nix:28)    go = 1.26.7, go_1_27 = 1.27.0    too old
  # so overlays/default.nix resolves go_1_27 from the `nixpkgs-go` input, which
  # exists for this one attribute and nothing else. All three versions MEASURED
  # 2026-09-23; see that input's comment in flake.nix.
  buildGo127Module = buildGoModule.override { go = go_1_27; };
in
buildGo127Module {
  pname = "ax";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "google";
    repo = "ax";
    rev = "d8ed0fe38bceb7842d3c47817d53d16ccdfcb601"; # = tag v0.3.0
    hash = "sha256-mGSQ4QsYLdeKDtVMBODCulqQQ0Ze0NjeADPhB6edaYU=";
  };

  # Obtained the ordinary way: build once with lib.fakeHash, read the "got:"
  # line off the failure, paste it back.
  vendorHash = "sha256-iC/X6Bg1M7Pn3dT1zWs2YxuPfgl9ZKNEYQsBisIQguY=";

  # Stock google/ax v0.3.0, no carried patches (Tom, 2026-09-23 08:45Z: "i
  # prefer not to patch ax itself unless we really have to"). The two patches
  # the bring-up carried were measured unnecessary on the 4-VM test
  # (evals-2026-09-23/zero-patch/zero-patch-combined.md, run 1 rc 0):
  #   - sandbox-class.patch: stock v0.3.0 already hardcodes
  #     SANDBOX_CLASS_GVISOR / gvisor-default (no-sandboxclass.md);
  #   - p1-completion.patch: a Task reports its own completion to the floor and
  #     the link deletes the Task, which frees the worker (no-p1.md). Stock ax
  #     keeps a finished Task Running until that delete.
  # Egress for a Task with no gateway is closed outside ax: the bootstrap
  # declares a default Gateway in every fleet atespace and
  # ax-fleet-gateway-default points gateway-less Tasks at it
  # (modules/ax-fleet/gateways.nix); the link refuses capacity on a missing
  # gateway (B10). Keep this list empty.
  patches = [ ];

  # subPackages left unset so all four commands build, matching upstream's
  # `make build-binaries` plus the cross-compiled runner. -s -w mirrors the
  # Makefile's ldflags.
  ldflags = [
    "-s"
    "-w"
  ];

  # Upstream's `make test` is `go test ./...`, and per docs/development.md it
  # "Runs everything, including the mock Substrate gRPC server, in-memory store
  # validation, and API server tests". It needs no cluster and no network, so it
  # is the one cluster-free regression proof this package has. Kept ON.
  doCheck = true;

  # MEASURED 2026-09-22: without git on PATH, two internal/workspace tests fail
  # with `exit status 127 ... git: command not found` (TestSetupWorkspace_GitSubdir
  # at setup_test.go:104, TestSetupWorkspace_GitDepth at setup_test.go:227). They
  # shell out to git to build a throwaway repo. This is a packaging fix, not a
  # source patch: nothing upstream is wrong.
  nativeCheckInputs = [ git ];

  meta = {
    description = "Kubernetes control plane for agent Tasks, delegating sandboxes to Agent Substrate";
    homepage = "https://github.com/google/ax";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "ax";
  };
}
