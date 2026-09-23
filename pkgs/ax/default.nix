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
# TWO CARRIED PATCHES in ./patches, applied in order, described at the `patches`
# entry below: sandbox-class.patch (a per-Task sandbox class) and
# p1-completion.patch (a finished command frees its worker). The upstream clone
# stays clean; each patch was extracted from a scratch copy of the fetched
# source, one commit per patch. The vendored Substrate client stays at
# 672533541dbf: no patch touches go.mod or go.sum.
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
  # line off the failure, paste it back. UNCHANGED by both patches, which
  # touch no go.mod or go.sum line and so vendors the same module set
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
  #
  # p1-completion.patch (REQUIRED for ax on the fleet). Stock v0.3.0 never learns
  # that a Task's command exited: the Task stays Running, its actor keeps its
  # worker, and a small WorkerPool is exhausted after a few finished Tasks
  # (MEASURED by the 2026-09-23 Substrate probe: the third Task on a 3-worker
  # pool failed ResourceExhausted; evals-2026-09-23/substrate/probe-build.md 4).
  # The patch:
  #   - runner: records the command's own exit and serves
  #     /metadata/v1alpha1/ax/{exit,result,usage} on the metadata port; result
  #     is the file at AX_RESULT_PATH (default <workspace>/.ax/result.json),
  #     capped at 1 MiB (413 above that, never truncated);
  #   - controller: a terminal guard (Completed, or Failed with Ready reason
  #     CommandExited, is never resumed again), an exit read after each resume,
  #     and a --running-resync loop (default 15s) that re-checks Running Tasks,
  #     because nothing publishes an event when a command exits. On exit it
  #     writes Completed (0) or Failed (Ready False CommandExited, ExitCode=N),
  #     TaskStatus.command, usage, stores the result, then SuspendActor frees
  #     the worker. A CRASHED actor with no exit report becomes Failed
  #     ActorCrashed instead of being silently recreated;
  #   - API: TaskStatus.command = 8, UsageStats.tool_calls = 3, rpc
  #     GetTaskResult (store key task-result:<atespace>:<name>), and
  #     `ax result task <name>`. ax.pb.go and ax_grpc.pb.go are regenerated
  #     with protoc-gen-go v1.36.11 and protoc-gen-go-grpc v1.6.2.
  # Its tests run in checkPhase below: the exit write-back for 0 and 3, the
  # terminal guard (the flipped probe TestProbe_CompletedWriteBackIsOverwritten),
  # the resync, a crashed actor, the runner's endpoints, and the floor test:
  # four Tasks in a row on a 2-worker pool all Completed, next to the contrast
  # that without an exit report the third is refused ResourceExhausted.
  # PROBE VARIANT probe/ax-fleet-nosc: sandbox-class.patch removed to measure
  # whether stock v0.3.0's hardcoded SANDBOX_CLASS_GVISOR / gvisor-default is
  # enough (evals-2026-09-23/zero-patch/no-sandboxclass.md). P1 kept.
  # PROBE VARIANT probe/ax-fleet-zeropatch: BOTH carried patches removed.
  # p1-completion.patch: completion is reported by the Task to the floor and
  # the link deletes the Task (no-p1.md). sandbox-class.patch: stock v0.3.0
  # already hardcodes SANDBOX_CLASS_GVISOR / gvisor-default (no-sandboxclass.md).
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
