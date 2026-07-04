{
  inputs,
  lib,
  config,
  ...
}:
# AMD Strix Halo layer — imported by `coordinator` + `worker` ONLY.
# NAMING RULE: the AMD pair is `coordinator` (main) + `worker` (compute). The names
# `companion` and `sodimo` NEVER appear. (See nix-decisions.md.)
{
  imports = [
    # Framework Desktop / Ryzen AI Max 300 series (gfx1151). Pulls amd cpu+gpu+ssd tuning.
    inputs.nixos-hardware.nixosModules.framework-desktop-amd-ai-max-300-series
  ];

  options.myCluster = {
    role = lib.mkOption {
      type = lib.types.enum [
        "coordinator"
        "worker"
      ];
      description = "Role on the AMD Strix Halo Thunderbolt cluster.";
    };
    tbHostId = lib.mkOption {
      type = lib.types.int;
      # coordinator=1, worker=2 → static thunderbolt0 IPs 10.77.0.{1,2}
      default = if config.myCluster.role == "coordinator" then 1 else 2;
      description = "Host id on the deterministic Thunderbolt link (drives the static /30).";
    };
  };

  config = {
    # Strix Halo unified-memory tuning (128 GiB pinnable for the iGPU; iommu off = lower latency).
    boot.kernelParams = [
      "amd_iommu=off"
      "ttm.pages_limit=33554432"
      # ttm.page_pool_size dropped — non-canonical (per the strix-halo research).
    ];

    # -------------------------------------------------------------------------
    # Thunderbolt cluster fabric — CONSUME myCluster (nix-test-compare WRONG list:
    # "myCluster.role/tbHostId declared but barely consumed … the TB /30 link is
    # comment-only. Adopt the option *and actually gate on it*"). Must exist from
    # first boot: ds4-dual-node-lessons.md burned days on NM link-local IPs +
    # firewall zones ("Headless-access saga collapses under … TB static IPs",
    # hosts/coordinator/default.nix). authorized_keys deliberately NOT declared
    # here (reserved for Tom).
    # -------------------------------------------------------------------------
    boot.kernelModules = [ "thunderbolt-net" ]; # host-to-host TB networking (thunderbolt0)

    # Deterministic static /30 on the direct TB cable; keep NetworkManager's hands
    # off it (the old NM-assigned 169.254.* link-local IPs were the fragile part).
    networking.networkmanager.unmanaged = [ "interface-name:thunderbolt0" ];
    networking.interfaces.thunderbolt0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.77.0.${toString config.myCluster.tbHostId}";
          prefixLength = 30;
        }
      ];
    };

    # Naming fabric: both nodes resolve both TB endpoints by role name
    # (-tb suffix so LAN/tailscale resolution of the plain hostnames is untouched).
    networking.hosts = {
      "10.77.0.1" = [ "coordinator-tb" ];
      "10.77.0.2" = [ "worker-tb" ];
    };

    # ds4-dual-node-lessons.md Lesson #5 + Appendix A: an untrusted TB interface
    # REJECTs cluster traffic ("No route to host") — coordinator :8081 inbound AND
    # worker inbound KV staging. Trust the point-to-point link on BOTH nodes.
    networking.firewall.trustedInterfaces = [ "thunderbolt0" ];
  };
}
