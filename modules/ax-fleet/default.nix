{
  config,
  lib,
  options,
  ...
}:
# ax on the fleet (DESIGN.md, ~/today/evals-2026-09-23/ax-fleet/). One import
# per host, one kill switch per host (`myAxFleet.enable`), three roles:
#
#   control   nas          k3s server + kubelet (untainted), Substrate and ax
#                          control planes, the registry. "Hypervisor on NAS."
#   harness   coordinator  k3s agent tainted ate.dev/sandboxClass=gvisor, the
#                          atelet DaemonSet and the gVisor WorkerPool. "Agent
#                          harnesses on coordinator."
#   inference worker       Halogen as today, as a host service. Nothing from
#                          this PR runs there; one evaluation assertion only.
#
# Folded in and deleted: modules/k3s-fleet.nix (#447; its CIDRs, assertions,
# feature gates and runtime-config are kept below and in ./k3s.nix; its Cilium,
# containerd template and runsc RuntimeClass are dropped because Substrate runs
# its own runsc inside the worker pods) and hosts/nas/state-services.nix (#446;
# only its registry is kept, in ./control.nix).
let
  cfg = config.myAxFleet;

  # ── CIDR arithmetic (from #447), so the overlap check is arithmetic ──
  ipToInt =
    s:
    let
      o = map lib.toInt (lib.splitString "." s);
      at = builtins.elemAt o;
    in
    (at 0) * 16777216 + (at 1) * 65536 + (at 2) * 256 + (at 3);

  cidrRange =
    c:
    let
      parts = lib.splitString "/" c;
      base = ipToInt (builtins.head parts);
      bits = lib.toInt (builtins.elemAt parts 1);
      size = builtins.foldl' (a: _: a * 2) 1 (lib.range 1 (32 - bits));
    in
    {
      lo = base;
      hi = base + size - 1;
    };

  overlaps =
    a: b:
    let
      x = cidrRange a;
      y = cidrRange b;
    in
    x.lo <= y.hi && y.lo <= x.hi;

  inCidr = ip: c: overlaps "${ip}/32" c;

  roleHost = {
    control = "nas";
    harness = "coordinator";
    inference = "worker";
  };
in
{
  imports = [
    ./interface.nix
    ./k3s.nix
    ./control.nix
    ./harness.nix
    ./inference.nix
    ./substrate.nix
    ./ax.nix
    ./gateways.nix
  ];

  config = lib.mkMerge [
    {
      # ── OUTSIDE THE GATE, ON PURPOSE (kept from #447) ──────────────────
      # k3s's own default pod range (10.42.0.0/16) contains the house LAN.
      # These evaluate on every host whether or not the fleet is enabled, so
      # an edit to a CIDR fails `nix eval`, not the house's DNS.
      assertions = [
        {
          assertion = !(overlaps cfg.podCidr cfg.lan.cidr);
          message = "modules/ax-fleet: the pod CIDR ${cfg.podCidr} overlaps the house LAN ${cfg.lan.cidr}.";
        }
        {
          assertion = !(overlaps cfg.serviceCidr cfg.lan.cidr);
          message = "modules/ax-fleet: the service CIDR ${cfg.serviceCidr} overlaps the house LAN ${cfg.lan.cidr}.";
        }
        {
          assertion = !(overlaps cfg.podCidr cfg.serviceCidr);
          message = "modules/ax-fleet: the pod CIDR ${cfg.podCidr} and the service CIDR ${cfg.serviceCidr} overlap.";
        }
        {
          assertion = inCidr cfg.clusterDns cfg.serviceCidr && inCidr cfg.axServerClusterIP cfg.serviceCidr;
          message = "modules/ax-fleet: clusterDns and axServerClusterIP must sit inside the service CIDR ${cfg.serviceCidr}.";
        }
      ];
    }

    (lib.mkIf cfg.enable {
      assertions = [
        {
          # The test VMs carry the production hostnames, so this holds there too.
          assertion = config.networking.hostName == roleHost.${cfg.role};
          message = "modules/ax-fleet: ${config.networking.hostName} has role \"${cfg.role}\", which belongs to ${roleHost.${cfg.role}}. nas is control, coordinator is harness, worker is inference.";
        }
        {
          assertion = inCidr cfg.lan.address cfg.lan.cidr;
          message = "modules/ax-fleet: lan.address ${cfg.lan.address} is not inside lan.cidr ${cfg.lan.cidr}.";
        }
        {
          assertion = cfg.role != "control" || cfg.lan.address == cfg.serverAddress;
          message = "modules/ax-fleet: the control node's LAN address (${cfg.lan.address}) must equal serverAddress (${cfg.serverAddress}).";
        }
      ];
    })

    # One switch per host: the harness role brings the ax and kubectl clients
    # (modules/ax-client.nix, #454) with it. mkDefault, so a host can still
    # say no. Guarded on the option existing: the NAS does not import
    # ax-client.nix.
    (lib.mkIf (cfg.enable && cfg.role == "harness") (
      lib.optionalAttrs (options ? myAxClient) {
        myAxClient.enable = lib.mkDefault true;
      }
    ))
  ];
}
