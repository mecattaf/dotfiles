{
  config,
  lib,
  ...
}:
# The inference node: the worker. "Halogen inference mainly on worker" (Tom,
# 2026-09-23), and since 2026-09-25 a k3s agent of the NAS as well. Tom's
# ruling that day, verbatim: "the amd strix halo worker SHOULD be available in
# the cluster (not just halogen inference)".
#
# Available, not used: the node registers tainted `inferenceTaint`
# (ax.mecattaf.dev/role=inference:NoSchedule) and labelled
# ate.dev/substrate-version=none, so nothing that runs today lands here.
# Substrate's control pods, CoreDNS and local-path tolerate only the
# not-ready/unreachable/control-plane keys and sit on the NAS by elimination;
# atelet selects the substrate version and the WorkerPool the harness role
# (MEASURED live and in substrate.nix, fleet map 2026-09-25). A workload runs
# here only once it tolerates the taint; which one comes first is Tom's call.
#
# Halogen stays the worker's host service (podman, host network, outside the
# cluster). Sandboxes on the coordinator still reach it at halogenEndpoint
# through Substrate's egress gateway on the NAS (SNAT to the NAS's LAN
# address); the taint keeps atenet-egress on the NAS, so that path and the
# NAS's port enforcement are unchanged.
#
# The shared agent half (guards, owner match, VXLAN peers, the
# NetworkManager drop-in) is ./agent.nix. This file is what is the worker's
# alone: the agent's registration, a kubelet that leaves Halogen its memory,
# Halogen's CPU weight, and the 8731 assertion.
let
  cfg = config.myAxFleet;
  on = cfg.enable && cfg.role == "inference";
  port = lib.toInt (lib.last (lib.splitString ":" cfg.halogenEndpoint));
  lanPorts = config.networking.firewall.interfaces.${cfg.lan.interface}.allowedTCPPorts or [ ];
in
{
  config = lib.mkIf on {
    assertions = [
      {
        assertion = builtins.elem port lanPorts;
        message = "modules/ax-fleet/inference.nix: Halogen's port ${toString port} must stay open on ${cfg.lan.interface}; ax sandboxes reach ${cfg.halogenEndpoint} through the egress gateway on the NAS.";
      }
    ];

    services.k3s = {
      # Never the default "server" (k3s.nix asserts it): a server here would
      # start its own cluster on 10.42.0.0/16, the house LAN.
      role = "agent";
      # The IP, not the name `nas`.
      serverAddr = "https://${cfg.serverAddress}:6443";
      # From the first registration: k3s applies --node-taint when the node
      # registers, and an untainted first join would let a rescheduled
      # Substrate control pod (atenet-egress among them, which would then
      # bypass the NAS's "Halogen port only" pod-egress guard) land here.
      nodeTaint = [ cfg.inferenceTaint ];
      # `none`, as on the NAS: ate-setup labels only nodes that lack the key
      # (DESIGN D5/D6), so without it a later 30-substrate run would label the
      # worker with the version and atelet (version-keyed) would land here.
      nodeLabel = [
        "ax.mecattaf.dev/role=inference"
        "ate.dev/substrate-version=none"
      ];
    };

    myAxFleet.kubelet = {
      # Halogen's memory lives outside every cgroup kubelet could protect
      # (MEASURED live 2026-09-25: the libpod scope 4.1 GB, the GTT 46.4 GB,
      # page cache 77 GB, of 125 GiB; modules/halogen.nix budgets ~68 GiB of
      # weights plus a ~35 GB KV pool, and page-cache starvation has killed a
      # working server before). So the protection is a hard cap on
      # kubepods.slice through a large system-reserved, not an eviction
      # threshold: 125 - 100 - 2 leaves kubepods about 23 GiB, allocatable
      # about 19 GiB. A proposal from those readings, to be checked after the
      # join (kubectl describe node worker; /stats/summary). Whether kubelet's
      # memory.available counts the GTT is not measured.
      systemReserved = lib.mkDefault "cpu=8,memory=100Gi";
      kubeReserved = lib.mkDefault "cpu=1,memory=2Gi";
      # Every signal, not only memory (harness.nix, fix round 4): a set
      # --eviction-hard REPLACES kubelet's whole default map.
      evictionHard = lib.mkDefault "memory.available<4Gi,nodefs.available<10%,nodefs.inodesFree<5%,imagefs.available<15%,imagefs.inodesFree<5%";
    };

    # ── CPU: Halogen outweighs the pods ──
    # The Halogen container's scope lives in machine.slice (MEASURED
    # machine.slice/libpod-*.scope), weight 100 by default, against
    # kubepods.slice's kubelet-computed weight (INFERRED 899 for 32 - 8 - 1 =
    # 23 allocatable CPUs, harness.nix's formula). Work-conserving: idle CPU
    # still goes to the pods.
    systemd.slices.machine.sliceConfig.CPUWeight = lib.mkDefault 10000;
  };
}
