{
  inputs,
  lib,
  config,
  pkgs,
  ...
}:
# AMD Strix Halo layer — imported by `coordinator` + `worker` ONLY. The role
# remains meaningful after soft retirement: it selects per-machine accelerator
# policy, not a requirement for a physical two-node fabric.
{
  imports = [
    # Framework Desktop / Ryzen AI Max 300 series (gfx1151). Pulls amd cpu+gpu+ssd tuning.
    inputs.nixos-hardware.nixosModules.framework-desktop-amd-ai-max-300-series
    # Shared accelerated inference/tooling packages from nix-strix-halo plus the
    # one noamsto-only GPU backend. Host-role details stay in that module.
    ./strix-ai.nix
    # Native local-model proxy/control plane on coordinator + worker only.
    ./llama-swap.nix
    # Typed model catalog, guarded store materialization, and host projections.
    ./local-models.nix
  ];

  options.myCluster = {
    role = lib.mkOption {
      type = lib.types.enum [
        "coordinator"
        "worker"
      ];
      description = "Hardware-policy role in the AMD Strix Halo fleet.";
    };
  };

  config = {
    # THE one model-install switch. Keep false until the reviewed roster and the
    # external cold-storage migration are ready; false roots zero model weights.
    services.local-models.downloadAllModels = false;

    # The gfx1151 ROCm graph contains several split Composable Kernel derivations,
    # each of which honors NIX_BUILD_CORES internally. Leaving both knobs at the
    # 32-thread defaults allowed up to 32 derivations with 32 compiler processes
    # apiece and exhausted 128 GiB during the first MLX build. Four eight-core
    # jobs keep all 32 hardware threads useful without multiplying parallelism.
    nix.settings = {
      max-jobs = 4;
      cores = 8;
    };

    # One TUI for CPU, Radeon iGPU, and (on the coordinator) XDNA NPU telemetry.
    environment.systemPackages = [ pkgs.amdtop ];

    # Strix Halo unified-memory tuning (128 GiB pinnable for the iGPU).
    # IOMMU is the ONE per-role knob: the coordinator runs the NPU, whose amdxdna
    # driver binds via IOMMU SVA/PASID and needs IOMMU ON in translated mode
    # (hardware.amd-npu additionally pins iommu.passthrough=0). The worker keeps
    # the NPU off and takes amd_iommu=off for lower GPU-memory latency / max iGPU.
    boot.kernelParams = [
      (if config.myCluster.role == "coordinator" then "amd_iommu=on" else "amd_iommu=off")
      "ttm.pages_limit=33554432"
    ];

    # --- mt7925e (RZ717 wifi) crash hardening, 2026-07-16 ---
    # The MT7925 driver has a remaining wcid list-corruption race on the STA
    # teardown/setup path (kernel BUG at lib/list_debug.c:32 → instant hard
    # lockup: LEDs on, zero video, zero network, manual power-cycle needed).
    # Fired twice on the coordinator within 12h of the BIOS 3.02→3.05 update
    # after weeks of silence on 3.02 — prime suspect is 3.05 changing PCIe
    # ASPM/power-state timing. Kernel 7.1 already has the upstream fixes for
    # the KNOWN instances of this bug class (zbowling v7 series), so until the
    # remaining race is fixed upstream we keep the card out of ASPM low-power
    # states via the driver's own escape hatch. Cost: ~1W idle. Both nodes
    # carry the same RZ717 card. The roam TRIGGER is separately removed by the
    # BSSID pin in hosts/coordinator/uplink-nas.nix.
    boot.extraModprobeConfig = "options mt7925e disable_aspm=1";

    # Hardware watchdog (sp5100_tco, /dev/watchdog0 — present but unfed until
    # now): systemd pets it at runtime; if the kernel ever hard-locks again
    # (this bug or the next one) the chip force-resets the box after 30s
    # instead of it sitting "on but dead" overnight until someone finds it —
    # the exact 2026-07-16 failure mode, twice. rebootTime bounds a hung
    # reboot/shutdown the same way.
    systemd.settings.Manager = {
      RuntimeWatchdogSec = "30s";
      RebootWatchdogSec = "2m";
    };

  };
}
