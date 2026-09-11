{
  config,
  lib,
  pkgs,
  ...
}:
# Halogen Flash — the fleet's one inference server.
#
# Qwen3.8-Flash-Next served by Peonist's closed-source engine
# (ghcr.io/peonist-ai/halogen-flash-server), built for gfx1151 and nothing
# else. It is an OCI image and only an OCI image: the ROCm 7.14 userland is
# bundled inside it, so the host contributes exactly the amdgpu driver,
# /dev/kfd, /dev/dri and a directory of weights. There is no model catalogue,
# no swapping and no second model — the engine holds the box (~116 GiB of
# mlocked weights plus a reserved KV pool) for the life of the process, which
# is why it runs on the worker alone and the coordinator only dials it.
#
# Launch shape lifted from kyuz0/ai-toolbox-cockpit
# (ai_toolbox_cockpit/backends/halogen/runner.py + the halogen-strix-halo
# runtime profile in assets/toolboxes.json): the same device nodes, seccomp
# unconfined, host IPC, unlimited memlock, and the HALOGEN_* environment that
# is the server's entire configuration surface (docs/FLAGS.md upstream: no
# config file, every flag read once at startup).
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

  bundleCheck = pkgs.writeShellScript "halogen-bundle-check" ''
    set -u
    dir=${lib.escapeShellArg bundle.directory}
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
    '') bundle.files}
    if [ "$fail" != 0 ]; then
      echo "halogen: the ${cfg.artifact} bundle is incomplete under $dir." >&2
      echo "halogen: loan it from the NAS Library first: sudo local-models-borrow --dry-run, then --yes." >&2
      exit 1
    fi
  '';

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

    image = lib.mkOption {
      type = lib.types.str;
      # Pinned by digest, never by tag: upstream ships more than one release a
      # day and a floating tag would re-pull a different engine on a restart.
      # Bump deliberately; the digest is the one printed by
      #   skopeo inspect docker://ghcr.io/peonist-ai/halogen-flash-server:<tag>
      default = "ghcr.io/peonist-ai/halogen-flash-server@sha256:c738212d7ecc5f5288f0dca9173b2d0f0188b9fde94e7ee07f074d71f8152d89";
      description = "OCI image reference (release 0.5.6 by digest).";
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

    lanInterface = lib.mkOption {
      type = lib.types.str;
      default = "enp191s0";
      description = "The only interface the unauthenticated API is admitted on.";
    };

    contextPositions = lib.mkOption {
      type = lib.types.ints.positive;
      default = 262144;
      description = "HALOGEN_CTX — the widest single request; the native context is the maximum without YaRN.";
    };

    kvPoolPositions = lib.mkOption {
      type = lib.types.ints.positive;
      default = 524288;
      description = "HALOGEN_KV_POOL_POSITIONS — the memory knob (about 35 GB at the default).";
    };

    kvSlots = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "HALOGEN_KV_SLOTS — conversations decoding at once.";
    };

    promptCache = lib.mkOption {
      type = lib.types.enum [
        "0"
        "1"
        "2"
      ];
      default = "2";
      description = "HALOGEN_PROMPT_CACHE — 2 resumes any shared prefix, 1 exact repeats only, 0 off.";
    };

    vision = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Load the vision tower so image_url content parts are accepted (OCR lives here).";
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
      ];

      virtualisation.oci-containers.backend = "podman";
      virtualisation.oci-containers.containers.halogen = {
        image = cfg.image;
        autoStart = true;
        volumes = [ "${bundle.directory}:/models:ro" ];
        environment = {
          HALOGEN_CHECKPOINT = "/models/${artifact.source.primary}";
          HALOGEN_CK_OVERLAY = "/models/qwen38-flash-next-w4b.overlay.hgn";
          HALOGEN_TOKENIZER = "/models/tokenizer";
          HALOGEN_MODEL_ID = cfg.modelId;
          HALOGEN_API_PORT = toString cfg.port;
          HALOGEN_CTX = toString cfg.contextPositions;
          HALOGEN_KV_POOL_POSITIONS = toString cfg.kvPoolPositions;
          HALOGEN_KV_SLOTS = toString cfg.kvSlots;
          HALOGEN_PROMPT_CACHE = cfg.promptCache;
        }
        // lib.optionalAttrs cfg.vision {
          HALOGEN_VISION_TOWER = "/models/qwen38-flash-next-vision.hgn";
        };
        extraOptions = [
          "--network=host"
          "--device=/dev/kfd"
          "--device=/dev/dri"
          "--group-add=keep-groups"
          "--security-opt=seccomp=unconfined"
          "--ipc=host"
          "--ulimit=memlock=-1:-1"
        ];
      };

      systemd.services.podman-halogen = {
        preStart = lib.mkBefore "${bundleCheck}\n";
        # mkForce throughout: the oci-containers module writes its own values
        # for these (no start timeout, restart always) and they are the wrong
        # ones for a 20-minute cold load.
        serviceConfig = {
          # A cold start reads ~68 GB off NVMe and upstream budgets 20 minutes
          # for it; a slow disk has been seen past 30.
          TimeoutStartSec = lib.mkForce "45min";
          TimeoutStopSec = lib.mkForce "2min";
          # The engine's own watchdog exits the process on a wedged GPU queue so
          # that a restart policy can recover it.
          Restart = lib.mkForce "on-failure";
          RestartSec = lib.mkForce "30s";
        };
      };

      networking.firewall.interfaces.${cfg.lanInterface}.allowedTCPPorts = [ cfg.port ];

      # Upstream's published reference boot line for a 128 GB Strix Halo
      # (README "Conditions"): GTT sized to the box, no VM update mode, no
      # retry on faults, no scatter-gather display. amd_iommu=off and the TTM
      # page limit come from modules/strix.nix.
      boot.kernelParams = [
        "amdgpu.gttsize=126976"
        "amdgpu.vm_update_mode=0"
        "amdgpu.noretry=0"
        "amdgpu.sg_display=0"
      ];
    })

    (lib.mkIf cfg.client.enable {
      environment.systemPackages = [ utilityRunner ];
    })
  ];
}
