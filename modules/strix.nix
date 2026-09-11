{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# AMD Strix Halo layer — imported by `coordinator` and `worker`, the two
# identical Ryzen AI MAX+ 395 (gfx1151) boxes. Everything above the roster is
# uniform: same silicon, same accelerator stack, same crash hardening, same
# unified-memory tuning. Only WHICH models each box is authorized to materialize
# differs, and that is selected below by networking.hostName.
#
# It used to be selected by `myCluster.role`, a bespoke enum option this module
# declared. That option is GONE (the flake asserts its absence) — it duplicated
# the hostname with an extra failure mode, namely a host whose role and name
# disagreed. Reading the hostname is the same pattern modules/secrets.nix uses
# for its per-host tiers, so the fleet now has one idiom instead of two.
{
  imports = [
    # Framework Desktop / Ryzen AI Max 300 series (gfx1151). Pulls amd cpu+gpu+ssd tuning.
    inputs.nixos-hardware.nixosModules.framework-desktop-amd-ai-max-300-series
    # XDNA2 NPU stack — both boxes expose it.
    inputs.nix-amd-ai.nixosModules.default
    # Accelerated inference/tooling packages from nix-strix-halo plus the one
    # noamsto-only GPU backend.
    ./strix-ai.nix
    # Typed model catalog, guarded store materialization, and host projections.
    ./local-models.nix
    # The fleet's one inference server (the worker enables it) and the
    # utility-model client that dials it (the coordinator enables that).
    ./halogen.nix
  ];

  config = {
    # What each twin WANTS on its own NVMe under /var/lib/local-models — the
    # exact set local-models-borrow loans from the NAS Library and
    # local-models-prune keeps. Nothing here serves a model: the worker's
    # bundle is served by modules/halogen.nix, the coordinator's small GGUFs by
    # a hand-run llama-server. The catalogue (lib/local-models.nix) stays
    # broader than either list — embeddings, VibeVoice speech and Mage rows are
    # loanable on demand — and the NAS Library keeps every row regardless.
    services.local-models.artifacts =
      lib.optionals (config.networking.hostName == "worker") [
        "halogen-qwen38-flash-next"
        "halogen-qwen38-27b"
      ]
      ++ lib.optionals (config.networking.hostName == "coordinator") [
        "qwen36-35b-a3b-mtp-ud-q8-k-xl"
        "gemma4-12b-it-q8-0"
        "gemma4-12b-it-mtp-q8-0"
        "fara15-9b-q8-0"
        "fara15-9b-mmproj-bf16"
      ];

    # NPU DECOMMISSIONED 2026-08-29: Tom forgoes the XDNA2 NPU permanently.
    # The nix-amd-ai import stays — its overlay is applied unconditionally and
    # keeps pkgs.fastflowlm resolvable — but this gate removes amdxdna, the
    # accel udev rules, the XRT env vars, the @video/@render memlock limits,
    # and the flm package from both twins. Recovery is flipping these back and
    # restoring the catalog rows to canonical. (utility-model survived the
    # decommission: it migrated to the GPU seam the same day and now installs
    # via modules/halogen.nix on the coordinator only, dialing the worker's
    # Halogen server.)
    #
    # The memlock loss is not a serving regression: the Halogen container runs
    # with an unlimited memlock ulimit of its own (modules/halogen.nix), so the
    # GPU inference path never depended on the @video/@render limits this gate
    # drops.
    #
    # linux 7.2 ships amdxdna IN-TREE, so disabling the nix-amd-ai module no
    # longer keeps the driver off the bus — observed bound (0 users) on the
    # worker's first 7.2 boot. Blacklist it: the NPU is decommissioned and,
    # with amd_iommu=off, unusable regardless. Remove this line on revival.
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
    # Weights archived at /mnt/nas/models/weights/flm/. Tom may choose to revive
    # the NPU on this device specifically for gemma4-it:e4b (Gemma4-E4B-IT-NPU2 —
    # ad-hoc multimodal utility) and qwen3.6-moe:35b-a3b (Qwen3.6-35B-A3B-NPU2 —
    # the drain's next OCR engine, OCR-validation still pending) if flm is ever
    # brought back. Recovery = restore modules/npu-llm.nix from git history and
    # re-import it above (deleted 2026-08-31 with the appliance tier, #270 —
    # its `services.npu-llm.enable = false` line went with it, since setting an
    # undeclared option fails eval) + uncomment the roster below + flip the
    # enables in hardware.amd-npu above + restore the catalog rows to canonical
    # (their backend value "npu" is retired-only in lib/local-model-backends.nix
    # and must be re-promoted) + `flm pull`, or restore the trees from the NAS
    # archive. AGENTS.md rules the NPU must never come back as part of the
    # CURRENT design; this block is the record of what a reversal would restore,
    # not an invitation.
    # services.npu-llm = {
    #   enable = true;
    #   models =
    #     lib.optionals (config.networking.hostName == "coordinator") [
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

    # ── Linux 7.2 on the twins (#244) ──────────────────────────────────────
    #
    # Same sourcing doctrine as hosts/nas/kernel.nix, applied to the boxes that
    # actually motivated the migration:
    #
    #   * The main `nixpkgs` pin predates 7.2 (it sits at 7.1.4) and does NOT
    #     move for this — it gates the whole Mesa/ROCm userland these two boxes
    #     are built around, and dragging it forward to chase a kernel would
    #     re-qualify the entire gfx1151 inference stack.
    #   * freshPkgs.linuxPackages_latest — rejected: it would silently jump to
    #     7.3 the next time nixpkgs-fresh moves for something unrelated.
    #   * linuxPackages_7_2 — CHOSEN: the versioned attr advances only within
    #     the 7.2.x stable series (point fixes yes, series jumps never), and
    #     when 7.2 ages out of nixpkgs entirely eval breaks LOUDLY and this
    #     stanza gets a deliberate successor. Fail-loud, not drift.
    #
    # Why now: 7.1.4 carries the amdgpu ISM dc_lock reboot deadlock (#244) —
    # the twins can wedge on the way down and need a hand at the power button.
    # 7.2 fixes it. No mkForce: modules/common.nix:45 sets kernelPackages with
    # mkDefault, so this plain assignment wins on both twins.
    #
    # Nothing out-of-tree rides this kernel, so a 7.2.x point release is just
    # a point release.
    boot.kernelPackages =
      (import inputs.nixpkgs-fresh {
        inherit (pkgs.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      }).linuxPackages_7_2;

    # Strix Halo unified-memory tuning.
    #
    # ttm.pages_limit=33554432 is 33554432 × 4 KiB = exactly 128 GiB, i.e. the
    # whole machine: a deliberate CEILING for a box whose entire point is that
    # the iGPU reaches system RAM. It is NOT a memory policy and it reserves
    # nothing — amdgpu sizes the GTT pool from it and then clamps to system
    # RAM (measured on both twins: "Capping GTT to 128087M", gtt_total =
    # MemTotal to the byte), so today the RAM cap, not this number, sets the
    # pool. Push it below MemTotal and it becomes load-bearing directly.
    # The worker's Halogen server plans its KV pool against that GTT figure
    # (modules/halogen.nix); whoever lowers this ceiling re-checks
    # HALOGEN_KV_POOL_POSITIONS in the same change.
    #
    # IOMMU is explicitly OFF since the 2026-08-29 NPU decommission. It was on
    # for amdxdna, the only consumer on these boxes that ever needed translated
    # mode; with amdxdna gone nothing on the twins does, so the DMA translation
    # cost buys nothing — and Halogen's own measurements put amd_iommu=off at
    # 13–16 % of prefill.
    #
    # watchdog.stop_on_reboot=0 keeps sp5100_tco armed across the reboot
    # transition (#244 checklist): the watchdog exists precisely to catch a box
    # that hangs on the way down, which is exactly when the kernel would
    # otherwise disarm it.
    boot.kernelParams = [
      "amd_iommu=off"
      "ttm.pages_limit=33554432"
      "watchdog.stop_on_reboot=0"
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
