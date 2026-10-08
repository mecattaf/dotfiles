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
    ./halogen.nix
  ];

  config = {
    services.local-models.artifacts = [
      "halogen-qwen38-flash-next"
      "halogen-qwen38-27b"
    ]
    ++ lib.optionals (config.networking.hostName == "strix") [
      # The one diarization model (Tom, 2026-09-16), loaded by call-diarize.
      "vibevoice-asr-streaming-7b-bf16"
    ];

    services.halogen = {
      enable = true;
      autoStart = true;
      lanInterface = "enp191s0";
      # The one serving default this fleet overrides. The image ships 8192,
      # which bounds REASONING AND CONTENT TOGETHER against a chat template
      # whose own effort is xhigh: a turn that thinks past the budget returns
      # finish_reason "length" with EMPTY content and the whole reply stranded
      # in reasoning_content. Most OpenAI clients do not render that field, and
      # at least one agent harness reads it as "no assistant message" and
      # retries — deterministically, at temperature 0, forever. Every client
      # that dials these servers is agentic (utility-model, pi,
      # academic-ocr-drain), so that failure is a matter of when.
      #
      # 16384 is upstream's own suggested step for agentic traffic and is what
      # the reporter on upstream #44 runs on the same silicon. The cost is pool
      # reservation, since a request reserves prompt + budget when admitted:
      # four slots at 16384 is 65536 of the 524288-position pool before a
      # single prompt token, which the box has room for many times over.
      maxTokensDefault = 16384;
      healthKill = true;
      kvPoolPositions = if config.networking.hostName == "strix" then 262144 else null;
      # The alternate model: Qwen3.8-27B under halogen-server. Never resident
      # together with Flash — `halogen-switch qwen38-27b` stops the Flash unit
      # and starts this one; `halogen-switch flash` goes back.
      #
      # halogen-server 0.1.4 (2026-09-16), reference checkout ~/today/halogen-
      # server @ 5a0f952: a serving-only release over 0.1.3 (same kernels,
      # checkpoint and weights) that honours chat_template_kwargs, accepts the
      # developer role, keeps idle connections 300 s, accepts reasoning_effort
      # "none", 400s response_format and reports /health.version. Digest
      # re-resolved with `skopeo inspect docker://ghcr.io/peonist-ai/halogen:0.1.4`.
      #
      # What this engine does NOT offer, checked inside the 0.1.4 image:
      #   * no /usr/local/bin/halogen-healthcheck, so it gets no podman health
      #     options (Flash's observe-then-kill check cannot be copied);
      #   * no default-budget env knob: serve_api.py hardcodes max_tokens 8192
      #     (the /health field max_tokens_default), so the empty-content trap
      #     Flash's maxTokensDefault = 16384 closes is open here — agentic
      #     clients must send max_tokens themselves. HALOGEN_MAX_TOKENS_CAP
      #     (65536) and HALOGEN_QUEUE_TIMEOUT (7200) stay the image's coupled
      #     pair, unset here.
      # HALOGEN_DOWNLOAD stays unset (model-byte doctrine) and the tokenizer is
      # the bundle's flat tokenizer/ directory.
      #
      # No --security-opt seccomp=unconfined, although upstream's run lines
      # still carry it: 0.1.4 was run on the strix (2026-09-17) with
      # exactly the shared containerOptions and no seccomp flag, loaded the
      # checkpoint, reported /health version.match true and answered a chat
      # completion. Same conclusion upstream reached for Flash in 0.6.1.
      alternates.qwen38-27b = {
        image = "ghcr.io/peonist-ai/halogen@sha256:dc0a39a0016d6cfc58a197978febaafdf8d28403f724ded6111d98b5fb7ac0ea";
        artifact = "halogen-qwen38-27b";
        modelId = "halogen-qwen3.8-27b";
        # KV_SLOTS stays the image's 1 (speculation on). On the strix the
        # prompt cache gets a fixed 8 GiB budget instead of auto-sizing from
        # MemAvailable at startup, which on a desktop would claim whatever the
        # TTS, ASR and browser happen not to be using at that moment.
        environment = lib.optionalAttrs (config.networking.hostName == "strix") {
          HALOGEN_CACHE_MB = "8192";
        };
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
