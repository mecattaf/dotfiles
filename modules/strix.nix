{ inputs, lib, ... }:
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
      type = lib.types.enum [ "coordinator" "worker" ];
      description = "Role on the AMD Strix Halo Thunderbolt cluster.";
    };
    tbHostId = lib.mkOption {
      type = lib.types.int;
      default = 1; # coordinator=1, worker=2 → static thunderbolt0 IPs 10.77.0.{1,2}
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
  };
}
