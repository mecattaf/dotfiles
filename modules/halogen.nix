{
  config,
  lib,
  pkgs,
  ...
}:
# Halogen Flash — the fleet's language-model server, declared on both twins.
#
# Qwen3.8-Flash-Next served by Peonist's closed-source engine
# (ghcr.io/peonist-ai/halogen-flash-server), built for gfx1151 and nothing
# else. It is an OCI image and only an OCI image: the ROCm 7.14 userland is
# bundled inside it, so the host contributes exactly the amdgpu driver,
# /dev/kfd, /dev/dri and a directory of weights. There is no model catalogue
# and no hot swapping — the engine holds the box (~68 GiB of locked weights
# plus a reserved KV pool) for the life of the process. The worker keeps it
# resident from boot and is the fleet's `utility` endpoint; the coordinator
# declares the same server with autoStart = false (Tom, 2026-09-16), because a
# resident model there would starve the desktop, TTS and diarization.
#
# Launch shape now tracks UPSTREAM'S OWN docker-compose.yml, not
# kyuz0/ai-toolbox-cockpit, which is where it came from originally. Cockpit is
# the stalest of the references as of 2026-09-13: it pins 0.5.4, still marks
# the backend "experimental", and its runtime profile still carries the
# seccomp=unconfined that upstream measured to be a no-op and dropped in 0.6.1.
# Upstream's compose file is the file upstream keeps current and it carries the
# reasoning for every line in comments; read that before changing this one.
# The HALOGEN_* environment is the server's entire configuration surface
# (docs/FLAGS.md upstream: no config file, every flag read once at startup).
#
# WHAT THIS MODULE DELIBERATELY DOES NOT SET: anything whose value would merely
# restate the image's own default. A copy of a default in a second file is a
# copy that goes stale — it silently pins last release's value through an image
# bump — so every tuning option below is nullOr/null and is emitted into the
# container environment ONLY when an operator has actually chosen something.
# `null` means "whatever the image ships", which is the correct answer for all
# of them today.
#
# Weights follow the fleet's model-byte doctrine (DECISIONS.md 2026-09-10):
# the bundle is a catalogue artifact (lib/local-models.nix,
# halogen-qwen38-flash-next), the NAS Library fetches it from Hugging Face,
# and an operator loans it onto this host with `local-models-borrow --yes`.
# The service never downloads: HALOGEN_DOWNLOAD stays unset, the mount is
# read-only, and the pre-start check refuses to launch a 20-minute cold load
# against an incomplete bundle.
#
# The API (OpenAI-compatible on :8731, /health for liveness) has NO
# authentication. It is published on the host network and admitted on the
# LAN interface only; every client on that segment is a pinned house device.
# The engine's own token protocol (:8730) binds loopback inside the host
# namespace and is never admitted.
let
  cfg = config.services.halogen;
  catalog = import ../lib/local-models.nix { inherit lib; };
  modelStore = import ../lib/model-store.nix { inherit catalog lib; };
  bundle = modelStore.materialized.${cfg.artifact};
  artifact = catalog.artifacts.${cfg.artifact};
  hasFile = name: lib.any (file: file.name == name) bundle.files;

  bundleCheckFor =
    artifactId:
    let
      b = modelStore.materialized.${artifactId};
    in
    pkgs.writeShellScript "halogen-bundle-check-${artifactId}" ''
      set -u
      dir=${lib.escapeShellArg b.directory}
      fail=0
      ${lib.concatMapStringsSep "\n" (file: ''
        f="$dir/${file.name}"
        if [ ! -f "$f" ]; then
          echo "halogen: MISSING $f" >&2
          fail=1
        elif [ "$(${pkgs.coreutils}/bin/stat -c %s "$f")" != "${toString file.bytes}" ]; then
          echo "halogen: WRONG SIZE $f (want ${toString file.bytes} bytes)" >&2
          fail=1
        fi
      '') b.files}
      if [ "$fail" != 0 ]; then
        echo "halogen: the ${artifactId} bundle is incomplete under $dir." >&2
        echo "halogen: loan it from the NAS Library first: sudo local-models-borrow --dry-run, then --yes." >&2
        exit 1
      fi
    '';
  bundleCheck = bundleCheckFor cfg.artifact;

  # The one launch shape, shared by the Flash server and every alternate.
  containerOptions = [
    "--network=host"
    "--device=/dev/kfd"
    "--device=/dev/dri"
    "--group-add=keep-groups"
    # No seccomp=unconfined. It sat here until 0.6.1, when upstream measured it
    # to do nothing (public issue #8: the image starts and serves without it
    # under Podman) and dropped it from the compose file and both run commands.
    # --ipc=host is the one that IS load-bearing: without it the GPU runtime
    # dies ~2 s into startup, and no shm_size substitutes for it.
    "--ipc=host"
    "--ulimit=memlock=-1:-1"
  ];

  # The image ships /usr/local/bin/halogen-healthcheck. In `api` mode it makes
  # /health ask the ENGINE for a PONG before answering, so it is a check on the
  # pair rather than on the front end's own process — which is the whole point:
  # upstream measured a green TCP connect and a green /health in front of an
  # engine whose GPU queue had aborted, with every request hanging forever.
  #
  # WHY THIS IS SAFE TO ARM, AND ONLY NOW. A watchdog on this server used to be
  # actively dangerous: reading the model's 47.7 GiB n-gram lookup table was the
  # one step that could not answer a PING, so on a host short of page cache a
  # WORKING server went unanswered for minutes and got killed as a wedge —
  # twice, to one reporter (upstream #10, #22). 0.5.9 made that read answer PING
  # on the same cadence as the rest of a prefill and 0.6.3 made the read itself
  # ~40x faster. Both are in the 0.7.0 image this module pins. Do not backport
  # this block to an older digest.
  #
  # The numbers are deliberately slacker than upstream's compose (10s/3):
  # 30 s x 5 means roughly three minutes of sustained silence before a verdict,
  # which is past any transient this box has ever shown, and start-period
  # covers the cold load.
  #
  # IT SHIPS OBSERVE-ONLY. The binary's path is asserted by upstream's
  # docker-compose.yml and by nothing else: the published deploy/entrypoint.sh
  # never names it (it runs /usr/local/bin/flash_serve), and upstream has
  # shipped a published tree that lagged its own image on exactly that file
  # (0.6.1 changelog). A wrong path would make every probe fail, and with
  # --health-on-failure=kill that is a kill loop against a server that is fine.
  # So healthKill stays false until the path is confirmed ON THE BOX:
  #
  #   podman healthcheck run halogen && echo OK
  #   podman inspect halogen --format '{{json .State.Health}}'
  #
  # Once that reports healthy, set services.halogen.healthKill = true and the
  # unhealthy verdict becomes a non-zero exit, which unitPolicy's
  # Restart=on-failure below then recovers from. That is the whole point of
  # having the check, so do not leave it observe-only indefinitely.
  healthOptions = [
    "--health-cmd=/usr/local/bin/halogen-healthcheck api"
    "--health-interval=30s"
    "--health-timeout=35s"
    "--health-retries=5"
    "--health-start-period=20m"
  ]
  ++ lib.optional cfg.healthKill "--health-on-failure=kill";
  # mkForce throughout: the oci-containers module writes its own values for
  # these (no start timeout, restart always) and they are the wrong ones for
  # a cold load measured in tens of minutes.
  unitPolicy = {
    TimeoutStartSec = lib.mkForce "45min";
    TimeoutStopSec = lib.mkForce "2min";
    # The engine's own watchdog exits the process on a wedged GPU queue so
    # that a restart policy can recover it.
    Restart = lib.mkForce "on-failure";
    RestartSec = lib.mkForce "30s";
  };

  alternateNames = builtins.attrNames cfg.alternates;
  unitOf =
    name: if name == "flash" then "podman-halogen.service" else "podman-halogen-${name}.service";
  allUnits = map unitOf ([ "flash" ] ++ alternateNames);
  # One resident model at a time: the operator's switch between them. `off`
  # stops every Halogen unit, which is how an on-demand host (autoStart =
  # false) hands its GPU back.
  halogenSwitch = pkgs.writeShellApplication {
    name = "halogen-switch";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      choice=''${1:-}
      case "$choice" in
        ${lib.concatMapStringsSep " | " (n: "${n}") ([ "flash" ] ++ alternateNames ++ [ "off" ])}) ;;
        *)
          echo "usage: halogen-switch <${lib.concatStringsSep "|" ([ "flash" ] ++ alternateNames ++ [ "off" ])}>" >&2
          echo "Stops whichever Halogen server is resident and starts the named one (a cold load: minutes); off stops them all." >&2
          exit 64
          ;;
      esac
      case "$choice" in
        flash) unit=podman-halogen.service ;;
        off) unit= ;;
        *) unit="podman-halogen-$choice.service" ;;
      esac
      for u in ${lib.escapeShellArgs allUnits}; do
        [ "$u" = "$unit" ] || systemctl stop "$u"
      done
      [ -n "$unit" ] || exit 0
      systemctl start "$unit"
      systemctl --no-pager status "$unit" | head -5
    '';
  };

  utilityRunner = pkgs.writeShellApplication {
    name = "utility-model";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../pkgs/utility-model/utility_model.py} "$@" \
        --endpoint ${lib.escapeShellArg cfg.client.endpoint} \
        --concrete-model ${lib.escapeShellArg cfg.modelId} \
        --context-tokens ${toString cfg.client.contextTokens}
    '';
  };
in
{
  options.services.halogen = {
    enable = lib.mkEnableOption "the Halogen Flash server, as a podman container on this host";

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether the Flash server starts at boot. False declares the server
        without making it resident: an operator starts it (or an alternate)
        with `halogen-switch` and releases the GPU with `halogen-switch off`.
      '';
    };

    image = lib.mkOption {
      type = lib.types.str;
      # Pinned by digest, never by tag: upstream ships more than one release a
      # day and a floating tag would re-pull a different engine on a restart.
      # Bump deliberately; the digest is the one printed by
      #   skopeo inspect docker://ghcr.io/peonist-ai/halogen-flash-server:<tag>
      default = "ghcr.io/peonist-ai/halogen-flash-server@sha256:ddbdf632035483e5e716a136e7111aff1f8d963f77787dd4fcc4758cc91206c4";
      description = "OCI image reference (release 0.7.0 by digest).";
    };

    artifact = lib.mkOption {
      type = lib.types.str;
      default = "halogen-qwen38-flash-next";
      description = "Catalogue artifact holding the .hgn bundle; mounted read-only at /models.";
    };

    modelId = lib.mkOption {
      type = lib.types.str;
      default = "halogen-qwen3.8-flash-next";
      description = "The label the API answers to (HALOGEN_MODEL_ID). Requests naming another id are still served.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8731;
      description = "The OpenAI-compatible front end (HALOGEN_API_PORT).";
    };

    healthKill = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether an unhealthy verdict kills the container so the restart policy
        recovers it (--health-on-failure=kill). Ships false: see the note above
        healthOptions — arm it only after `podman healthcheck run halogen`
        has been seen to succeed on this host.
      '';
    };

    lanInterface = lib.mkOption {
      type = lib.types.str;
      default = "enp191s0";
      description = "The only interface the unauthenticated API is admitted on.";
    };

    contextPositions = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = ''
        HALOGEN_CTX — the widest single request. null leaves the image's own
        value, which is 262144, the model's full native context and the most
        it will take without a static YaRN factor.
      '';
    };

    kvPoolPositions = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = ''
        HALOGEN_KV_POOL_POSITIONS — the memory knob. null leaves the image's
        own value, 2 x HALOGEN_CTX (524288, about 35 GB on the device, two
        full-length conversations resident). Lower it to 262144 to give the
        n-gram lookup table more page cache; the server also lowers it itself
        when the configured pool will not fit and says which it chose.
      '';
    };

    kvSlots = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = ''
        HALOGEN_KV_SLOTS — conversations decoding at once. null leaves the
        image's own value of 4. This is a latency policy, not a memory
        decision: the slots share one pool and each costs only ~115 MB.
      '';
    };

    promptCache = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "0"
          "1"
          "2"
        ]
      );
      default = null;
      description = ''
        HALOGEN_PROMPT_CACHE — 2 resumes any shared prefix, 1 exact repeats
        only, 0 off. null leaves the image's own value, 2. Note 2 is the one
        NUMERIC setting here: a resumed answer is usually, not always, what a
        cold run would have produced. Set "1" for anything audited.
      '';
    };

    overlay = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        HALOGEN_CK_OVERLAY — which precision sidecar to read. null is the
        quality sidecar beside the checkpoint, which needs no action and is
        what this fleet serves. The alternatives are the speed arm
        (…overlay-speed.hgn, ~2% more decode for the o_proj calibration) and
        "none" (the bare 4-bit checkpoint, a measurement control rather than a
        serving configuration). NUMERIC: it selects which weights run.
      '';
    };

    maxTokensDefault = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = ''
        HALOGEN_MAX_TOKENS_DEFAULT — the budget a request that sends none
        gets. null leaves the image's own 8192 on chat and responses.

        Worth knowing before leaving it null: this budget bounds REASONING AND
        CONTENT TOGETHER, and the chat template's own reasoning effort is
        xhigh. A turn that thinks past the budget does not come back short, it
        comes back EMPTY — `finish_reason: "length"`, empty `content`, the whole
        reply stranded in `reasoning_content`, which most OpenAI clients do not
        display and at least one agent harness reads as "no assistant message"
        and retries, deterministically, forever. Upstream's own suggested step
        for agentic traffic is 16384. Every client on this fleet is agentic.
      '';
    };

    vision = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Load the vision tower so image_url content parts are accepted (OCR lives here).";
    };

    alternates = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            image = lib.mkOption {
              type = lib.types.str;
              description = "OCI image reference, pinned by digest.";
            };
            artifact = lib.mkOption {
              type = lib.types.str;
              description = "Catalogue artifact holding the .hgn bundle (snapshot layout with tokenizer/).";
            };
            modelId = lib.mkOption {
              type = lib.types.str;
              description = "The id this server's /v1/models reports; informational for clients.";
            };
            environment = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "Extra HALOGEN_* flags for this engine.";
            };
          };
        }
      );
      default = { };
      description = ''
        Other Halogen engines on this host, one podman unit each
        (podman-halogen-<name>), sharing the Flash server's port and launch
        shape and never resident together with it or each other: the units
        carry mutual Conflicts=, none starts at boot, and `halogen-switch
        <name>` is how an operator brings one up in place of Flash.
      '';
    };

    client = {
      enable = lib.mkEnableOption "the utility-model wrapper that forwards one request to the fleet's Halogen server";

      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "http://worker:8731";
        description = "Where the fleet's Halogen server answers.";
      };

      contextTokens = lib.mkOption {
        type = lib.types.ints.positive;
        default = 131072;
        description = "Prompt budget the utility-model wrapper plans against.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = artifact.source.layout == "snapshot" && hasFile "tokenizer/tokenizer.json";
          message = "services.halogen.artifact must be a snapshot bundle carrying tokenizer/ beside the checkpoint.";
        }
        {
          assertion = !cfg.vision || hasFile "qwen38-flash-next-vision.hgn";
          message = "services.halogen.vision needs the vision tower in the bundle.";
        }
        {
          assertion = lib.elem cfg.artifact config.services.local-models.artifacts;
          message = "services.halogen.artifact must be in this host's services.local-models.artifacts so the bundle is a wanted, loanable working copy.";
        }
        {
          assertion = lib.all (alt: lib.elem alt.artifact config.services.local-models.artifacts) (
            builtins.attrValues cfg.alternates
          );
          message = "Every services.halogen.alternates.<name>.artifact must be in this host's services.local-models.artifacts.";
        }
        {
          assertion = !(cfg.alternates ? flash) && !(cfg.alternates ? off);
          message = "services.halogen.alternates may not be named `flash` (the primary server) or `off` (halogen-switch's stop verb).";
        }
      ];

      virtualisation.oci-containers.backend = "podman";
      virtualisation.oci-containers.containers = {
        halogen = {
          image = cfg.image;
          inherit (cfg) autoStart;
          volumes = [ "${bundle.directory}:/models:ro" ];
          environment = {
            # Paths and labels: facts about how this bundle is mounted, not
            # copies of a default, so they are always written.
            HALOGEN_CHECKPOINT = "/models/${artifact.source.primary}";
            HALOGEN_TOKENIZER = "/models/tokenizer";
            HALOGEN_MODEL_ID = cfg.modelId;
            HALOGEN_API_PORT = toString cfg.port;
            # HALOGEN_CK_OVERLAY is NOT set here. Unset already means "the
            # quality sidecar beside the checkpoint", which is the file we
            # loan, so naming it bought nothing and would have had to be
            # re-checked at every bump. cfg.overlay below is the escape hatch.
          }
          // lib.optionalAttrs (cfg.contextPositions != null) {
            HALOGEN_CTX = toString cfg.contextPositions;
          }
          // lib.optionalAttrs (cfg.kvPoolPositions != null) {
            HALOGEN_KV_POOL_POSITIONS = toString cfg.kvPoolPositions;
          }
          // lib.optionalAttrs (cfg.kvSlots != null) {
            HALOGEN_KV_SLOTS = toString cfg.kvSlots;
          }
          // lib.optionalAttrs (cfg.promptCache != null) {
            HALOGEN_PROMPT_CACHE = cfg.promptCache;
          }
          // lib.optionalAttrs (cfg.overlay != null) {
            HALOGEN_CK_OVERLAY = cfg.overlay;
          }
          // lib.optionalAttrs (cfg.maxTokensDefault != null) {
            HALOGEN_MAX_TOKENS_DEFAULT = toString cfg.maxTokensDefault;
          }
          // lib.optionalAttrs cfg.vision {
            HALOGEN_VISION_TOWER = "/models/qwen38-flash-next-vision.hgn";
          };
          extraOptions = containerOptions ++ healthOptions;
        };
      }
      // lib.mapAttrs' (
        name: alt:
        lib.nameValuePair "halogen-${name}" {
          image = alt.image;
          autoStart = false;
          volumes = [ "${modelStore.materialized.${alt.artifact}.directory}:/models:ro" ];
          environment = {
            HALOGEN_CHECKPOINT = "/models/${catalog.artifacts.${alt.artifact}.source.primary}";
            HALOGEN_TOKENIZER = "/models/tokenizer";
            HALOGEN_API_PORT = toString cfg.port;
          }
          // alt.environment;
          extraOptions = containerOptions;
        }
      ) cfg.alternates;

      systemd.services = {
        podman-halogen = {
          preStart = lib.mkBefore "${bundleCheck}\n";
          conflicts = map unitOf alternateNames;
          serviceConfig = unitPolicy;
        };
      }
      // lib.mapAttrs' (
        name: alt:
        lib.nameValuePair "podman-halogen-${name}" {
          preStart = lib.mkBefore "${bundleCheckFor alt.artifact}\n";
          conflicts = map unitOf ([ "flash" ] ++ (lib.remove name alternateNames));
          serviceConfig = unitPolicy;
        }
      ) cfg.alternates;

      environment.systemPackages = [ halogenSwitch ];

      networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ cfg.port ];

      # GTT sized to the box. This is the half of upstream's reference boot
      # line that is a SIZE rather than a flag: GTT is where every allocation
      # this server makes on the GPU actually lands, and 126976 MiB is the
      # 128 GB row of upstream's table. It pairs with ttm.pages_limit in
      # modules/strix.nix, which says the same thing in 4 KiB pages; amd_iommu
      # =off lives there too and is the one setting upstream has actually A/B'd
      # (13-16% of prefill, and it takes the NPU with it — already decommissioned
      # here, so the trade is free for this fleet).
      #
      # THE OTHER THREE ARE GONE (2026-09-13): amdgpu.vm_update_mode=0,
      # amdgpu.noretry=0 and amdgpu.sg_display=0 were carried here as
      # "upstream's published reference boot line". Upstream rewrote that
      # paragraph in 0.6.1 and no longer recommends them: "listed for
      # completeness rather than recommended... unmeasured in both directions",
      # plus one report (#34) of an UNKILLABLE AMDGPU DEADLOCK from a boot that
      # had the first two set. This fleet has its own amdgpu deadlock history
      # (#244, the sp5100_tco watchdog in modules/strix.nix, journal-upload
      # existing so a hard lockup still leaves evidence), so carrying three
      # unmeasured amdgpu flags with a deadlock report attached to two of them
      # is a bet with no upside. sg_display was the clearest of the three:
      # it tunes the display scanout path on a box that has NO DISPLAY
      # (hosts/worker/default.nix — no compositor, no greeter, no VNC).
      #
      # These are BOOT parameters: they apply machine-wide at every boot, not
      # while the container runs, and dropping them takes effect on the next
      # reboot, not on the switch that removes them. Verify with /proc/cmdline.
      #
      # The coordinator carries this line too since it declares the server
      # (2026-09-16). Before its first reboot with it, that box already
      # measured gtt_total 134309523456 bytes (125 GiB) from ttm.pages_limit
      # alone, so its Halogen units do not wait on that reboot. It has a
      # display, so the sg_display reasoning above no longer applies fleet-wide
      # — but sg_display stays out regardless, for the deadlock report.
      boot.kernelParams = [
        "amdgpu.gttsize=126976"
      ];
    })

    (lib.mkIf cfg.client.enable {
      environment.systemPackages = [ utilityRunner ];
    })
  ];
}
