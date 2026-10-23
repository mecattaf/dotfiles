{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    # Framework Desktop / Ryzen AI Max 300 series (gfx1151). Pulls amd cpu+gpu+ssd tuning.
    inputs.nixos-hardware.nixosModules.framework-desktop-amd-ai-max-300-series
    # Hardware definitions only; the NPU remains disabled below.
    inputs.nix-amd-ai.nixosModules.default
    # Accelerated inference/tooling packages from nix-strix-halo plus the one
    # noamsto-only GPU backend.
    ./strix-ai.nix
    # Typed model catalog, guarded store materialization, and host projections.
    ./local-models.nix
    ./gufo.nix
    # The utility-model seam (/drain, /print), independent of the engine.
    ./utility-model.nix
  ];

  config = {
    services.local-models.artifacts = [
      # Gufo text bundles, borrowed from the NAS Library.
      "qwen38-flash-next-gguf"
      "qwen38-27b-gguf"
      "qwen38-27b-dflash2-gguf"
    ]
    ++ lib.optionals (config.myFleet.has "compute") [
      # The one diarization model (Tom, 2026-09-16), loaded by call-diarize.
      "vibevoice-asr-streaming-7b-bf16"
    ];

    # Gufo owns the local fleet endpoint; Gufo is retired.
    services.gufo = {
      enable = true;
      lanInterface = "enp191s0";
      alternates = {
        qwen38-27b = {
          artifact = "qwen38-27b-gguf";
          servedModelName = "qwen3.8-27b";
          mmproj = "mmproj-BF16.gguf";
          dflashArtifact = "qwen38-27b-dflash2-gguf";
          sessions = 4;
          context = 131072;
        };
        # Text only, 80.76 GiB: one session, as Gufo's docs run it.
        deepseek-v4-flash = {
          artifact = "deepseek-v4-flash-gguf";
          servedModelName = "deepseek-v4-flash";
          dsparkArtifact = "deepseek-v4-flash-dspark-gguf";
          sessions = 1;
          context = 32768;
        };
      };
      # The one voice (Tom, 2026-09-14): the K-2SO midway-B matched prefix and
      # its transcript. qwentts.cpp stays the live voice until Tom has listened
      # to Gufo's BF16 Base with it.
      tts.voices.k2so = {
        artifact = "qwen-k2so-midway-b";
        wav = "b-prefix.wav";
        text = "b-prefix.txt";
      };
    };

    boot.blacklistedKernelModules = [ "amdxdna" ];
    hardware.amd-npu = {
      enable = false;
      enableNPU = false;
      enableFastFlowLM = false;
      enableLemonade = false;
      enableROCm = false;
      lemonade.user = "tom";
    };

    # Retired 2026-08-29 with the NPU decommission. The roster below is kept as
    # commented Nix rather than deleted — it is the exact shape a revival would
    # restore. Its catalog rows are now status = "retired" with archive receipts
    # in lib/local-models.nix; the runtime-owned weights under ~/.config/flm/models
    # were freed by explicit `flm remove` (they are not store paths, so nothing
    # about them is GC-reachable), after being rsynced to the NAS.
    #
    # The NAS archive of those weights (/mnt/nas/models/weights/flm/) was
    # deleted 2026-09-16 with every Gemma and Qwen3.6 row (Tom's ruling), so a
    # revival would re-pull rather than restore. Recovery = restore
    # modules/npu-llm.nix from git history and
    # re-import it above (deleted 2026-08-31 with the appliance tier, #270 —
    # its `services.npu-llm.enable = false` line went with it, since setting an
    # undeclared option fails eval) + uncomment the roster below + flip the
    # enables in hardware.amd-npu above + restore the catalog rows to canonical
    # (their backend value "npu" is retired-only in lib/local-model-backends.nix
    # and must be re-promoted) + `flm pull`. AGENTS.md rules the NPU must never come back as part of the
    # CURRENT design; this block is the record of what a reversal would restore,
    # not an invitation.
    # services.npu-llm = {
    #   enable = true;
    #   models =
    #     lib.optionals (config.networking.hostName == "strix") [
    #       "gemma4-it:e4b"
    #       # gpt-oss:20b ruled out 2026-08-20 (old and outdated; dotfiles#229).
    #       # The catalog row is status = "retired"; the ~14G runtime-owned snapshot
    #       # under ~/.config/flm/models is freed by an explicit `flm remove`, not GC.
    #     ]
    #     ++ [
    #       # The drain's next OCR engine (24.3G, runtime-owned), carried on BOTH
    #       # boxes since its catalog row names both. Download stays the explicit
    #       # operator action `flm pull qwen3.6-moe:35b-a3b` — this module never
    #       # pulls — and it must be validated on OCR before any qwen3-vl / GPU-35B
    #       # removal that depends on it.
    #       "qwen3.6-moe:35b-a3b"
    #     ];
    # };

    # The gfx1151 ROCm graph contains several split Composable Kernel derivations,
    # each of which honors NIX_BUILD_CORES internally. Leaving both knobs at the
    # 32-thread defaults allowed up to 32 derivations with 32 compiler processes
    # apiece and exhausted 128 GiB during the first MLX build. Four eight-core
    # jobs keep all 32 hardware threads useful without multiplying parallelism.
    nix.settings = {
      max-jobs = 4;
      cores = 8;
    };

    boot.kernelPackages =
      (import inputs.nixpkgs-fresh {
        inherit (pkgs.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      }).linuxPackages_7_2;

    boot.kernelParams = [
      "amdgpu.gttsize=126976"
      "amd_iommu=off"
      "ttm.pages_limit=33554432"
      "watchdog.stop_on_reboot=0"
    ];

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
    # hosts/strix/nas-client.nix), so 2m keeps every plausible transient
    # stall inside the window while still catching real lockups within minutes,
    # not hours.
    systemd.settings.Manager = {
      RuntimeWatchdogSec = "2m";
      RebootWatchdogSec = "2m";
    };

  };
}
