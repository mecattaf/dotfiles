{
  lib,
  buildGoModule,
  fetchFromGitHub,
  applyPatches,
  # Passed in by the caller from the nixpkgs-go input, exactly as pkgs/ax gets
  # it (see overlays/default.nix and the nixpkgs-go comment in flake.nix).
  # Substrate's go.mod says `go 1.27.0`; the probe built it with 1.27.1
  # (MEASURED, evals-2026-09-23/substrate/probe-build.md section 2), and one
  # toolchain for ax and Substrate keeps the fleet on one Go.
  go_1_27,
}:
# Agent Substrate, the sandbox control plane ax delegates to. Upstream
# github.com/agent-substrate/substrate, pinned by commit to d277088b: the
# SERVER version the 2026-09-23 version rule names. ax keeps its own vendored
# CLIENT pin (672533541dbf); wire compatibility between the two is MEASURED
# (probe-build.md section 4).
#
# Not in nixpkgs. Upstream publishes no release images the fleet may use (the
# kagent-dev fork's ghcr images are ruled out), so every component image is
# built here and seeded into the NAS registry by pkgs/substrate/images.nix.
#
# The two patches touch only manifests/, never Go code:
#   0001 pauseImage -> localhost:5000/pause (atelet pulls it itself; the fleet
#        must not depend on registry.k8s.io at sandbox start).
#   0002 third-party images -> their linux/amd64 child digests, so the NAS
#        seeds ~0.7 GB instead of every platform (see the patch header).
# ate-setup reads the manifests from its working directory's repository root
# (it walks up to go.mod), so the patched tree is passthru.source and the
# bootstrap runs ate-setup from there.
let
  version = "d277088b";
  rev = "d277088bc1d081ef716d81dd7986d05d0a36ad3a";

  source = applyPatches {
    name = "substrate-source-${version}";
    src = fetchFromGitHub {
      owner = "agent-substrate";
      repo = "substrate";
      inherit rev;
      # nix-prefetch-url --unpack of the GitHub archive; the unpacked tree is
      # byte-identical to /home/tom/Downloads/substrate at this rev (MEASURED
      # diff -rq, 2026-09-23).
      hash = "sha256-/KY4vYgHbeiVnpRUsVFOVfoN3SVEtWJrXTj0Pb4Zeqw=";
    };
    patches = [
      ./patches/0001-sandboxconfig-pause-localhost.patch
      ./patches/0002-images-linux-amd64-digests.patch
    ];
  };

  buildGo127Module = buildGoModule.override { go = go_1_27; };

  # The six components the kind install and the WorkerPool run, plus the
  # installer. Image names are the import paths' last element, which is what
  # ate-setup's --image-repo mode looks up (cmd/ate-setup/internal/images).
  components = [
    "ateapi"
    "atecontroller"
    "atelet"
    "atenet"
    "podcertcontroller"
    "ateom-gvisor"
  ];
in
buildGo127Module {
  pname = "substrate";
  inherit version;
  src = source;

  # The tree is vendored (vendor/modules.txt), so no module download.
  vendorHash = null;

  subPackages = [ "cmd/ate-setup" ] ++ map (c: "cmd/${c}") components;

  env.CGO_ENABLED = "0";

  # The Makefile's LDFLAGS (Makefile:44-45), with the version the node label,
  # the image tag and ate-setup's VERSION all share.
  ldflags = [
    "-s"
    "-w"
    "-X=github.com/agent-substrate/substrate/internal/version.Version=${version}"
  ];

  # Upstream's suite needs Docker (225 PostgreSQL testcontainer tests), root
  # (19 tests) and an FHS /bin/sleep; the probe ran it outside nix (1422 pass,
  # 2 environment-only failures, MEASURED probe-build.md section 3). Inside the
  # nix sandbox it can only fail for the same environmental reasons.
  doCheck = false;

  passthru = {
    inherit
      source
      rev
      components
      ;
  };

  meta = {
    description = "Agent Substrate (upstream main ${version}): ate-setup and the gVisor control plane";
    homepage = "https://github.com/agent-substrate/substrate";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "ate-setup";
  };
}
