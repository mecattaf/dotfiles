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
    # Native local-model proxy/control plane.
    ./llama-swap.nix
    # Typed model catalog, guarded store materialization, and host projections.
    ./local-models.nix
    # ./npu-llm.nix was imported here until 2026-08-31 (#270): the FastFlowLM
    # roster module whose only live use was being asserted off since the
    # 2026-08-29 NPU decommission. Deleted with the appliance tier; a revival
    # restores it from git history (see the roster comment below).
    # PM QoS + MTU tuning for the coordinator<->worker rails. Declares an
    # option that defaults OFF; enabled below, so only these two boxes get it.
    ./lowlat-cluster.nix
    # Patched Thunderbolt core/net/ibverbs set, first-bound at boot (#241).
    # Same gate shape as lowlat-cluster: defaults OFF, enabled below.
    ./fn-rdma.nix
    # 7.2's in-tree USB4STREAM: udev perms + declarative stream groups on the
    # rail-0 cable. Same gate shape: defaults OFF, enabled below.
    ./usb4-stream.nix
  ];

  config = {
    # Explicit deployment authority. The catalog may remain broad; only these
    # per-host rows enter the system closure and llama-swap configuration.
    # modules/local-models.nix asserts that every ID listed here is canonical,
    # locally-backed, AND assigned to THIS host in lib/local-models.nix — so a
    # roster line on the wrong box is a build failure, not a runtime surprise.
    services.local-models = {
      allow =
        lib.optionals (config.networking.hostName == "coordinator") [
          "qwen36-35b-a3b-mtp-ud-q8-k-xl"
          "qwen36-27b-mtp-ud-q8-k-xl"
          "gemma4-26b-a4b-it-mtp-q8-0"
          "fara15-27b-q8-0"
          "fara15-9b-q8-0"
          # Ruled out 2026-08-20 (notes ACTION-PLAN §2b / dotfiles#229): rows stay
          # in the catalog; recovery is uncommenting a line here.
          # "fara15-4b-q8-0"
          # qwen3-vl-8b-ocr's exit condition used to be "the FastFlowLM Qwen 3.6
          # 35B NPU2 build validates on OCR" — that flip died with the NPU
          # decommission (2026-08-29; tier retired 2026-08-31, #270), so the row
          # stays until a GPU successor for the drain's OCR lane is validated
          # instead. Its former primary consumer — the paper-intake OCR
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
        ]
        # ── the worker's lane (#229, live 2026-08-21) ─────────────────────────
        # The two gemma4-31b rows have carried `hosts = [ "worker" ]` since the
        # MELS work and were inert for exactly as long as this host was absent
        # from the flake. They are the whole worker roster: the Google MELS lane
        # heavy model and its multimodal twin, sharing one Q8_0 weight set (the
        # -vl entry adds only the BF16 projector, and forgoes speculative
        # decoding because llama.cpp refuses to combine it with vision).
        #
        # Deliberately NOT mirrored from the coordinator: the twins have 128 GB
        # each, not 256 GB between them, and duplicating the qwen/fara rosters
        # would spend the worker's disk on weights the coordinator already
        # serves over the LAN for nothing in return. The split is the point.
        ++ lib.optionals (config.networking.hostName == "worker") [
          "gemma4-31b-it-q8-0"
          "gemma4-31b-it-vl"
        ];
      artifacts = [
        # BOTH twins, unconditionally: the flashnext TP=2 checkpoint is
        # tensor-parallel across coordinator AND worker, so each box needs the
        # complete 185.6 GB on its own NVMe (TP shards compute, not weights).
        # Listing it here is also what stops local-models-sync from pruning it:
        # an artifact absent from wanted.json is `rm -rf`'d on every boot,
        # rebuild, and sync-service start. That is not hypothetical — it
        # deleted the freshly staged checkpoint from both twins on 2026-08-29.
        # No llama-swap row: vLLM serves this one through its own pair service.
        "flashnext-fp8"
      ]
      ++ lib.optionals (config.networking.hostName == "coordinator") [
        # Priority Mage family: the unified VLM and the low-latency generation
        # and editing variants. Base and RL checkpoints are intentionally
        # omitted; their quality gain does not justify 5-7.5x more steps here.
        # These are immutable snapshot payloads; runtime services stay gated on
        # a proven ROCm package and do not become fake llama-swap rows.
        # Coordinator-only: every one of these is consumed by an interactive
        # or agent-side workflow that runs where Tom sits.
        "mage-vl-bf16"
        "mage-flow-4b-turbo-bf16"
        "mage-flow-edit-4b-turbo-bf16"
        "vibevoice-asr-bf16"
        "vibevoice-large-bf16"
        "vibevoice-qwen25-7b-tokenizer"
      ];
    };

    # NPU DECOMMISSIONED 2026-08-29: Tom forgoes the XDNA2 NPU permanently.
    # The nix-amd-ai import stays — its overlay is applied unconditionally and
    # keeps pkgs.fastflowlm resolvable — but this gate removes amdxdna, the
    # accel udev rules, the XRT env vars, the @video/@render memlock limits,
    # and the flm package from both twins. Recovery is flipping these back and
    # restoring the catalog rows to canonical. (utility-model survived the
    # decommission: it migrated to the GPU seam the same day and now installs
    # via modules/local-models.nix on the coordinator only, dialing llama-swap.)
    #
    # The memlock loss is not a serving regression: managed llama-swap sets its
    # own LimitMEMLOCK=infinity on its unit (modules/llama-swap.nix), so the GPU
    # inference path never depended on the @video/@render limits this gate drops.
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

    # The fleet rails' latency floor. Both twins hold /dev/cpu_dma_latency at
    # 0, because holding it on only ONE end is worth almost nothing (468 us
    # against 577 us unheld and 63-90 us held on both) — the remote wakeup
    # dominates the round trip. Enabling it here rather than per-host is the
    # point: this module is imported by exactly the two boxes that must agree,
    # so the both-ends invariant is structural instead of a deploy checklist.
    myLowLatCluster = {
      enable = true;
      # Each twin watches the other's end of the tb-fleet /30.
      peer = if config.networking.hostName == "coordinator" then "10.99.0.2" else "10.99.0.1";
      # jumbo stays off: see the two-step deploy note in the module. The
      # measured win is PM QoS; MTU buys throughput nothing has yet shown to
      # be short of.
    };

    # The patched Thunderbolt module set (#241) rides the same both-ends
    # logic: the matched core/net ABI is a per-host invariant, but ibverbs
    # USE needs both twins on the set, so it is enabled here — in the file
    # only the twins import — not per-host. Per-host escape stays runtime:
    # `touch /etc/fn-rdma-disable` + one attended reboot loads the stock pair.
    myFnRdma.enable = true;
    myUsb4Stream.enable = true;

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
    # The one string attached to this: the fn-rdma .ko set is vermagic-pinned
    # and its 7.2 re-bake is pending on the ATTENDED operator lane (#244,
    # host/rdma/fetch-and-build.sh). Until that set is staged, the loader takes
    # its sanctioned stock-thunderbolt fallback — the TB rails carry IP, just
    # without ibverbs. See modules/fn-rdma.nix `stagedDir`.
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
    # nothing. Kept at 128 GiB by ruling on #280, 2026-08-31, because it is
    # coupled to flashnext's per-rank claim — see the HAZARD below before
    # touching it.
    #
    # HAZARD — pages_limit and FN_GPU_UTIL are two unrelated mechanisms that
    # must be changed TOGETHER (#280).
    #   * amdgpu sizes the GTT pool from the TTM page limit and then clamps it
    #     to system RAM. Measured on BOTH twins, current boot:
    #         amdgpu: Capping GTT to 128087M to not exceed available system memory
    #         amdgpu: 128087M of GTT memory ready.
    #         mem_info_gtt_total = 134309523456 B = 125.085 GiB
    #                            = MemTotal (131161644 kB) to the byte
    #     So today the 128 GiB request sits ~2.9 GiB above what the kernel will
    #     grant, and the RAM cap — not this parameter — sets gtt_total. Push
    #     pages_limit BELOW MemTotal and it becomes load-bearing directly:
    #     gtt_total follows it down.
    #   * The actual policy is FN_GPU_UTIL=0.62 in flashnext's host/fn-env.sh,
    #     and it is a FRACTION OF GTT (fork patch 0004 points the engine's
    #     memory reporting at mem_info_gtt_total): 0.62 × 125.085 GiB =
    #     77.55 GiB/rank, which is the measured 76–78 GiB/rank. 0.62 was chosen,
    #     not defaulted — it keeps the rank under the 80 GiB residency bound
    #     receipts-verify grades (ruling P11) and leaves the ~40 GiB/node of
    #     page cache the mmap'd engram table is served from.
    #
    # Hence why #280's "lower the ceiling to ~96 GiB so the OS enforces the
    # reservation the application only promises" option was rejected: lowering
    # the ceiling shrinks gtt_total, and shrinking gtt_total silently shrinks
    # the engine's claim through that same 0.62 — 0.62 × 96 = 59.5 GiB/rank, an
    # ~18 GiB/rank cut to the very workload the change was meant to protect,
    # with no error and no log line. The "protection" would rewrite the
    # protected thing. A ceiling stays a ceiling.
    #
    # Enforcement of the ~40 GiB page-cache reservation therefore does not
    # belong to a kernel parameter. It belongs to #270: making the flashnext
    # lane a declared unit with its own accounting and a real arbitration
    # against llama-swap, which returns on every boot and every rebuild with
    # LimitMEMLOCK=infinity and is entitled to the same 125 GiB pool.
    #
    # Failure mode of getting this wrong is not an OOM and not an error: the
    # engram table's page cache is evicted and every table gather becomes an
    # NVMe fault — a decode-latency collapse that reads as a model or transport
    # problem, the most expensive class of bug on this estate. Idle 2026-08-31:
    # coordinator 93 GiB buff/cache, worker 20 GiB (the worker has not yet
    # faulted the table in, so the "cache is already full of what we must
    # protect" framing in #280 is coordinator-only). Whoever changes this
    # number changes host/fn-env.sh in the same breath, or measures why not.
    #
    # IOMMU is explicitly OFF since the 2026-08-29 NPU decommission. It was on
    # for amdxdna, the only consumer on these boxes that ever needed translated
    # mode; with amdxdna gone nothing on the twins does, so the DMA translation
    # cost buys nothing. (The old comment here also claimed hardware.amd-npu
    # pins iommu.passthrough=0 — the pinned nix-amd-ai never has; that claim was
    # already stale before this change.)
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
