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
# ONE PATCH, sandbox-class.patch, described at the `patches` entry below. It is
# the one the previous revision of this comment predicted: it makes the sandbox
# class per-Task instead of hardcoded. The upstream clone stays clean; the patch
# was extracted from a scratch copy of the fetched source.
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
  # line off the failure, paste it back. UNCHANGED by sandbox-class.patch, which
  # touches no go.mod or go.sum line and so vendors the same module set
  # (MEASURED 2026-09-23: the patched build reuses this hash).
  vendorHash = "sha256-iC/X6Bg1M7Pn3dT1zWs2YxuPfgl9ZKNEYQsBisIQguY=";

  # sandbox-class.patch adds `string sandbox_class = 11` to TaskSpec, regenerates
  # ax.pb.go with the same protoc-gen-go v1.36.11 upstream used, validates the
  # value in ValidateTask, and threads it from the reconciler through
  # BuildActorTemplate, replacing the SandboxClass_SANDBOX_CLASS_GVISOR hardcode
  # at internal/substrate/client.go:273. Empty means gvisor, so every existing
  # manifest behaves exactly as before.
  #
  # The generated Go is part of the patch on purpose: ax bridges YAML through
  # protojson with unknown fields REJECTED, so a .proto-only edit would make
  # every manifest naming sandboxClass fail strict decode.
  #
  # It does NOT give ax a workerd sandbox. Agent Substrate's SandboxClass enum
  # has exactly three members (UNSPECIFIED, GVISOR, MICROVM; MEASURED 2026-09-23
  # from the vendored ateapipb), so "gvisor" and "microvm" are the only values
  # that can reach a real substrate. A workerd class needs an upstream Agent
  # Substrate change that does not exist, and ax cannot invent the enum member.
  patches = [ ./sandbox-class.patch ];

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
