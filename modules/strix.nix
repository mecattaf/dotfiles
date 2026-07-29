{
  inputs,
  pkgs,
  ...
}:
# AMD Strix Halo layer for the coordinator.
{
  imports = [
    # Framework Desktop / Ryzen AI Max 300 series (gfx1151). Pulls amd cpu+gpu+ssd tuning.
    inputs.nixos-hardware.nixosModules.framework-desktop-amd-ai-max-300-series
    # XDNA2 NPU stack.
    inputs.nix-amd-ai.nixosModules.default
    # Accelerated inference/tooling packages from nix-strix-halo plus the one
    # noamsto-only GPU backend.
    ./strix-ai.nix
    # Native local-model proxy/control plane.
    ./llama-swap.nix
    # Typed model catalog, guarded store materialization, and host projections.
    ./local-models.nix
    # Deterministic FastFlowLM roster only; ad-hoc `flm run`, with no daemon.
    ./npu-llm.nix
  ];

  config = {
    # Explicit deployment authority. The catalog may remain broad; only these
    # per-host rows enter the system closure and llama-swap configuration.
    services.local-models = {
      allow = [
        "qwen36-35b-a3b-mtp-ud-q8-k-xl"
        "qwen36-27b-mtp-ud-q8-k-xl"
        "gemma4-26b-a4b-it-mtp-q8-0"
        "fara15-27b-q8-0"
        "qwen3-vl-8b-ocr"
        "qwen3-vl-32b-ocr-refine"
        "qwen3-embedding-8b-q8-0"
        "qwen3-vl-embedding-8b-q8-0"
      ];
      artifacts = [
        "vibevoice-asr-bf16"
        "vibevoice-large-bf16"
        "vibevoice-qwen25-7b-tokenizer"
      ];
    };

    # The coordinator exposes the XDNA2 NPU alongside its Radeon GPU.
    hardware.amd-npu = {
      enable = true;
      enableNPU = true;
      enableFastFlowLM = true;
      enableLemonade = false;
      enableROCm = false;
      lemonade.user = "tom";
    };

    services.npu-llm = {
      enable = true;
      models = [
        "gemma4-it:e4b"
        "gpt-oss:20b"
      ];
    };

    # The gfx1151 ROCm graph contains several split Composable Kernel derivations,
    # each of which honors NIX_BUILD_CORES internally. Leaving both knobs at the
    # 32-thread defaults allowed up to 32 derivations with 32 compiler processes
    # apiece and exhausted 128 GiB during the first MLX build. Four eight-core
    # jobs keep all 32 hardware threads useful without multiplying parallelism.
    nix.settings = {
      max-jobs = 4;
      cores = 8;
    };

    # One TUI for CPU, Radeon iGPU, and XDNA NPU telemetry.
    environment.systemPackages = [ pkgs.amdtop ];

    # Strix Halo unified-memory tuning (128 GiB pinnable for the iGPU).
    # amdxdna binds through IOMMU SVA/PASID and needs translated mode
    # (hardware.amd-npu additionally pins iommu.passthrough=0).
    boot.kernelParams = [
      "amd_iommu=on"
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
    # states via the driver's own escape hatch. Cost: ~1W idle. The roam trigger
    # is separately removed by the BSSID pin in hosts/coordinator/uplink-nas.nix.
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
