{
  inputs,
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
        "fara15-9b-q8-0"
        # Ruled out 2026-08-20 (notes ACTION-PLAN §2b / dotfiles#229): rows stay
        # in the catalog; recovery is uncommenting a line here.
        # "fara15-4b-q8-0"
        # qwen3-vl-8b-ocr stays UNTIL the FastFlowLM Qwen 3.6 35B NPU2 build is
        # validated on OCR. Its former primary consumer — the paper-intake OCR
        # processor — was removed 2026-08-20 with the returned ADS-1800W
        # scanner, so only the academic-ocr drain lane still dials this route;
        # weigh that when deciding whether it exits with the worker-drain flip.
        "qwen3-vl-8b-ocr"
        # "qwen3-vl-32b-ocr-refine"
        "qwen3-embedding-8b-q8-0"
        "qwen3-vl-embedding-8b-q8-0"
        # MELS fleet additions (#229): Qwen lane primary + wildcard companion.
        # Materialized at the next switch (~68G on the coordinator).
        "qwen38-27b-mtp-q8-0"
        "ornith-15-35b-q8-0"
      ];
      artifacts = [
        # Priority Mage family: the unified VLM and the low-latency generation
        # and editing variants. Base and RL checkpoints are intentionally
        # omitted; their quality gain does not justify 5-7.5x more steps here.
        # These are immutable snapshot payloads; runtime services stay gated on
        # a proven ROCm package and do not become fake llama-swap rows.
        "mage-vl-bf16"
        "mage-flow-4b-turbo-bf16"
        "mage-flow-edit-4b-turbo-bf16"
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
        # gpt-oss:20b ruled out 2026-08-20 (old and outdated; dotfiles#229).
        # The catalog row is status = "retired"; the ~14G runtime-owned snapshot
        # under ~/.config/flm/models is freed by an explicit `flm remove`, not GC.
        #
        # The drain's next OCR engine (24.3G, runtime-owned): download is the
        # explicit operator action `flm pull qwen3.6-moe:35b-a3b`, then validate
        # on OCR before any qwen3-vl / GPU-35B removal that depends on it.
        "qwen3.6-moe:35b-a3b"
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
    # (this bug or the next one) the chip force-resets the box after 2m
    # instead of it sitting "on but dead" overnight until someone finds it —
    # the exact 2026-07-16 failure mode, twice. rebootTime bounds a hung
    # reboot/shutdown the same way.
    #
    # 2m, not 30s: on 2026-08-02 a hung NFS mount stalled PID 1 mid
    # `nixos-rebuild switch` past the old 30s window and the TCO hard-reset a
    # live, recoverable box. The mount is soft-bounded now (~15s worst case,
    # hosts/coordinator/nas-client.nix), so 2m keeps every plausible transient
    # stall inside the window while still catching real lockups within minutes,
    # not hours.
    systemd.settings.Manager = {
      RuntimeWatchdogSec = "2m";
      RebootWatchdogSec = "2m";
    };

  };
}
