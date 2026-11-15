{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# Gufo: the fleet's native inference engine on Strix (dotfiles #525).
# The fleet uses its model collection (lib/gufo-models.json).
#
# Upstream is github:gufo-org/gufo (flake input `gufo`, pinned in flake.nix):
# one native `gufo` binary for gfx1151 with the model graphs, tokenizers and
# HIP kernels compiled in. No container. Each `gufo serve <modality>` process
# loads exactly ONE model, so this module runs one systemd unit per model:
#
#   llama-swap.service        the lightweight API endpoint, at boot when
#                             autoStart; models load only for requests
#   gufo-llm.service          explicit direct-mode text service, no boot target
#   gufo-llm-<name>.service   an alternate text model (the 27B), started
#                             directly by hand for diagnostics
#   gufo-tts / gufo-asr / gufo-image.service
#                             on demand only, loopback, no boot target
#
# Weights follow the fleet's model-byte doctrine: the catalog
# (lib/local-models.nix, lib/gufo-models.json) describes them, NAS
# library-fetch acquires them, `sudo local-models-borrow --yes` loans them to
# /var/lib/local-models. Neither build nor startup downloads anything; each
# unit checks its files before starting.
#
# Text model units conflict with one another and the image unit, so only
# one large model owns the GPU.
let
  cfg = config.services.gufo;
  catalog = import ../lib/local-models.nix { inherit lib; };
  modelStore = import ../lib/model-store.nix { inherit catalog lib; };

  dirOf = id: modelStore.materialized.${id}.directory;
  primaryOf = id: modelStore.materialized.${id}.primary;

  # Every file of the named artifacts present at its catalog size, or a clear
  # refusal naming the explicit borrow command.
  bundleCheckFor = import ../lib/model-bundle-check.nix { inherit lib pkgs modelStore; };

  # Startup returns only once the model answers, so `systemctl start` and
  # `gufo-switch` report a usable server, not a process that is still loading.
  waitReady =
    port: path:
    pkgs.writeShellScript "gufo-wait-ready" ''
      until ${pkgs.curl}/bin/curl -fsS -o /dev/null "http://127.0.0.1:${toString port}${path}"; do
        sleep 5
      done
    '';

  llmType = lib.types.submodule {
    options = {
      artifact = lib.mkOption {
        type = lib.types.str;
        description = "Catalog artifact holding the target model (its primary file is passed as --model).";
      };
      servedModelName = lib.mkOption {
        type = lib.types.str;
        description = ''
          The one model id this server answers to (--served-model-name). Gufo
          answers 404 to a text request naming any other id, so every caller
          must send exactly this.
        '';
      };
      mmproj = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Vision projector, relative to the artifact directory (--mmproj).";
      };
      mtp = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "MTP predictor, relative to the artifact directory (--speculative mtp --mtp-model).";
      };
      dflashArtifact = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Catalog artifact of a DFlash2 draft (--speculative dflash2 --dflash-model).";
      };
      dsparkArtifact = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Catalog artifact of a DSpark support model (--speculative dspark --dspark-model).";
      };
      sessions = lib.mkOption {
        type = lib.types.ints.positive;
        default = 2;
        description = "Execution session pool (--sessions): concurrent requests, each with its own state.";
      };
      context = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 32768;
        description = "Context per session (--context); 0 is the model's native context. Admission reserves it up front.";
      };
      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };
  };

  speculativeArgs =
    m:
    if m.mtp != null then
      [
        "--speculative"
        "mtp"
        "--mtp-model"
        "${dirOf m.artifact}/${m.mtp}"
      ]
    else if m.dflashArtifact != null then
      [
        "--speculative"
        "dflash2"
        "--dflash-model"
        (primaryOf m.dflashArtifact)
      ]
    else if m.dsparkArtifact != null then
      [
        "--speculative"
        "dspark"
        "--dspark-model"
        (primaryOf m.dsparkArtifact)
      ]
    else
      [ ];

  artifactsOf =
    m:
    [ m.artifact ]
    ++ lib.filter (a: a != null) [
      m.dflashArtifact
      m.dsparkArtifact
    ];

  llmArgs =
    m:
    [
      "serve"
      "llm"
      "--host"
      cfg.host
      "--port"
      (toString cfg.port)
      "--model"
      (primaryOf m.artifact)
      "--served-model-name"
      m.servedModelName
      "--sessions"
      (toString m.sessions)
      "--context"
      (toString m.context)
    ]
    ++ lib.optionals (m.mmproj != null) [
      "--mmproj"
      "${dirOf m.artifact}/${m.mmproj}"
    ]
    ++ speculativeArgs m
    ++ m.extraArgs;

  # The GPU, nothing else: a dynamic user in the render and video groups,
  # read-only weights, no home, no writable system paths.
  gpuServiceConfig = {
    DynamicUser = true;
    SupplementaryGroups = [
      "render"
      "video"
    ];
    LimitMEMLOCK = "infinity";
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    NoNewPrivileges = true;
    ReadOnlyPaths = [ modelStore.runtimeRoot ];
    # A cold load of a 100 GiB model from NVMe takes minutes.
    TimeoutStartSec = "45min";
    TimeoutStopSec = "2min";
    Restart = "on-failure";
    RestartSec = "30s";
  };

  apiIdOf =
    name: m: if lib.hasSuffix "-q8" name then "${m.servedModelName}-q8" else m.servedModelName;
  # Compatibility defaults for the established default/alternate declarations.
  # Generic deployment rendering and required loans live in gufo-models.nix.
  defaultModels =
    lib.mapAttrs' (
      name: m:
      lib.nameValuePair (apiIdOf name m) {
        inherit (m)
          artifact
          servedModelName
          mmproj
          mtp
          dflashArtifact
          dsparkArtifact
          ;
        serve = { inherit (m) sessions context extraArgs; };
      }
    ) ({ flash = cfg.llm; } // cfg.alternates)
    // {
      "qwen3-tts-12hz-1.7b-base" = {
        modality = "tts";
        inherit (cfg.tts) artifact voices;
      };
      "qwen3-asr-1.7b" = {
        modality = "asr";
        inherit (cfg.asr) artifact;
      };
      "Qwen-Image-2.1" = {
        modality = "image";
        inherit (cfg.image) artifact;
      };
    };

  alternateNames = builtins.attrNames cfg.alternates;
  unitOf = name: if name == "flash" then "gufo-llm.service" else "gufo-llm-${name}.service";
  textUnits = map unitOf ([ "flash" ] ++ alternateNames);

  mkLlmUnit = name: m: {
    description = "Gufo text model ${m.servedModelName} (${m.artifact})";
    conflicts = (lib.remove (unitOf name) textUnits) ++ [
      "gufo-image.service"
      "llama-swap.service"
    ];
    wantedBy = [ ];
    serviceConfig = gpuServiceConfig // {
      MemoryHigh = "96G";
      MemoryMax = "104G";
      MemorySwapMax = 0;
      ExecStartPre = "${bundleCheckFor (artifactsOf m)}";
      ExecStart = lib.escapeShellArgs ([ (lib.getExe' cfg.package "gufo") ] ++ llmArgs m);
      ExecStartPost = "${waitReady cfg.port "/ready"}";
    };
  };

  mkAuxUnit =
    {
      modality,
      artifact,
      port,
      args ? [ ],
      extraArtifacts ? [ ],
      conflicts ? [ ],
    }:
    {
      description = "Gufo ${modality} (${artifact}), on demand";
      conflicts = conflicts ++ [ "llama-swap.service" ];
      serviceConfig = gpuServiceConfig // {
        ExecStartPre = "${bundleCheckFor ([ artifact ] ++ extraArtifacts)}";
        ExecStart = lib.escapeShellArgs (
          [
            (lib.getExe' cfg.package "gufo")
            "serve"
            modality
            "--host"
            "127.0.0.1"
            "--port"
            (toString port)
            "--model"
            (dirOf artifact)
          ]
          ++ args
        );
        ExecStartPost = "${waitReady port "/ready"}";
      };
    };

  gufoSwitch = pkgs.writeShellApplication {
    name = "gufo-switch";
    runtimeInputs = [
      pkgs.systemd
      pkgs.curl
    ];
    text = ''
      choice=''${1:-}
      case "$choice" in
        ${lib.concatStringsSep " | " ([ "flash" ] ++ alternateNames ++ [ "off" ])}) ;;
        *)
          echo "usage: gufo-switch <${
            lib.concatStringsSep "|" ([ "flash" ] ++ alternateNames ++ [ "off" ])
          }>" >&2
          echo "Warm the named model through llama-swap (cold load: minutes); off stops the endpoint and its models." >&2
          exit 64
          ;;
      esac
      if [ "$choice" = off ]; then
        systemctl stop llama-swap.service ${lib.escapeShellArgs textUnits}
        exit 0
      fi
      case "$choice" in
        flash) model=${lib.escapeShellArg cfg.llm.servedModelName} ;;
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            name: m: "${lib.escapeShellArg name}) model=${lib.escapeShellArg (apiIdOf name m)} ;;"
          ) cfg.alternates
        )}
      esac
      systemctl start llama-swap.service
      ${waitReady cfg.port "/health"}
      curl --fail --silent --show-error --max-time 1200 "http://127.0.0.1:${toString cfg.port}/upstream/$model/ready"

    '';
  };
in
{
  imports = [ ./gufo-models.nix ];

  options.services.gufo = {
    enable = lib.mkEnableOption "Gufo, the local inference engine (one systemd unit per model)";

    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.gufo.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "inputs.gufo.packages.\${system}.default";
      description = "The gfx1151 gufo build.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the lightweight llama-swap endpoint starts at boot. Models load only on demand.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Listen address of the text server; the firewall below decides who reaches it.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8731;
      description = "The fleet API port, owned by llama-swap or an explicitly selected direct-mode service.";
    };

    lanInterface = lib.mkOption {
      type = lib.types.str;
      default = "enp191s0";
      description = "The only interface the unauthenticated text API is admitted on.";
    };

    openLanPort = lib.mkOption {
      type = lib.types.bool;
      default = cfg.autoStart;
      defaultText = lib.literalExpression "config.services.gufo.autoStart";
      description = "Whether to admit `port` on `lanInterface` (the host is the fleet's endpoint). Loopback is never filtered.";
    };

    demand = {
      textIdleSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 600;
        description = "Unload idle text/image models after this many seconds. In-flight requests prevent unload.";
      };
      audioIdleSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 120;
        description = "Unload idle Gufo TTS/ASR models after this many seconds.";
      };
      startPort = lib.mkOption {
        type = lib.types.port;
        default = 18731;
        description = "First private loopback backend port assigned by llama-swap; never opened in the firewall.";
      };
    };

    llm = lib.mkOption {
      type = llmType;
      default = {
        artifact = "qwen38-flash-next-gguf";
        servedModelName = "qwen3.8-flash-next";
        mmproj = "mmproj-BF16.gguf";
        mtp = "MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf";
        sessions = 1;
        context = 102400;
        extraArgs = [
          "--think"
          "off"
          "--cache-ram-bytes"
          "1073741824"
          "--max-tokens"
          "16384"
          "--max-pending"
          "8"
          "--request-timeout-ms"
          "1200000"
          "--stall-timeout-ms"
          "180000"
        ];
      };
      description = "The default text model, demand-loaded through llama-swap.";
    };

    alternates = lib.mkOption {
      type = lib.types.attrsOf llmType;
      default = { };
      description = ''
        Other text models, one unit each (gufo-llm-<name>.service), on the
        same port, never resident together with the primary or each other.
        API model IDs select them through llama-swap; `gufo-switch` explicitly warms a model.
      '';
    };

    tts = {
      artifact = lib.mkOption {
        type = lib.types.str;
        default = "qwen3-tts-12hz-1.7b-base";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 8735;
      };
      voices = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              artifact = lib.mkOption { type = lib.types.str; };
              wav = lib.mkOption { type = lib.types.str; };
              text = lib.mkOption { type = lib.types.str; };
            };
          }
        );
        default = { };
        description = "Reference voices (--voice NAME=WAV --voice-text NAME=TXT), paths relative to the voice artifact.";
      };
    };

    asr = {
      artifact = lib.mkOption {
        type = lib.types.str;
        default = "qwen3-asr-1.7b";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 8736;
      };
    };

    image = {
      artifact = lib.mkOption {
        type = lib.types.str;
        default = "qwen-image-2.1";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 8737;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.gufo.models = lib.mapAttrs (
      _: row:
      lib.mapAttrs (
        key: value: if key == "serve" then lib.mapAttrs (_: lib.mkDefault) value else lib.mkDefault value
      ) row
    ) defaultModels;

    assertions = [
      {
        # The resident model only. An alternate whose artifacts this host does
        # not want or has not borrowed yet is refused at start by its bundle
        # check, which names the borrow command.
        assertion = lib.all (a: lib.elem a config.services.local-models.artifacts) (artifactsOf cfg.llm);
        message = "The resident Gufo model's artifacts (services.gufo.llm) must be in this host's services.local-models.artifacts.";
      }
      {
        assertion = !(cfg.alternates ? flash) && !(cfg.alternates ? off);
        message = "services.gufo.alternates may not be named `flash` (the primary) or `off` (gufo-switch's stop verb).";
      }
    ];

    services.llama-swap = {
      enable = true;
      package = pkgs.llama-swap.override { withUI = false; };
      listenAddress = cfg.host;
      inherit (cfg) port;
      openFirewall = false;
      settings = {
        healthCheckTimeout = 1200;
        logLevel = "info";
        logTimeFormat = "rfc3339";
        logToStdout = "both";
        captureBuffer = 0;
        performance.disabled = true;
        startPort = cfg.demand.startPort;
        unloadTimeout = 90;
        # No preload hooks or custom groups: the upstream default swaps one
        # backend at a time, including across text, speech and image routes.
      };
    };

    systemd.services = {
      llama-swap = {
        wantedBy = lib.mkForce (lib.optional cfg.autoStart "multi-user.target");
        conflicts = textUnits ++ [
          "gufo-image.service"
          "gufo-tts.service"
          "gufo-asr.service"
        ];
        serviceConfig = (builtins.removeAttrs gpuServiceConfig [ "RestartSec" ]) // {
          MemoryHigh = "96G";
          MemoryMax = "104G";
          MemorySwapMax = 0;
        };
      };
      gufo-llm = mkLlmUnit "flash" cfg.llm;

      gufo-tts = mkAuxUnit {
        modality = "tts";
        inherit (cfg.tts) artifact port;
        extraArtifacts = lib.unique (lib.mapAttrsToList (_: v: v.artifact) cfg.tts.voices);
        args = lib.concatLists (
          lib.mapAttrsToList (name: v: [
            "--voice"
            "${name}=${dirOf v.artifact}/${v.wav}"
            "--voice-text"
            "${name}=${dirOf v.artifact}/${v.text}"
          ]) cfg.tts.voices
        );
      };

      # Per job only: speech input stays out (Tom, 2026-09-30), so nothing
      # starts this at boot or keeps it running.
      gufo-asr = mkAuxUnit {
        modality = "asr";
        inherit (cfg.asr) artifact port;
      };

      # 31 GiB of BF16 weights do not fit beside Flash-Next, so it takes the
      # GPU from every text unit while it runs.
      gufo-image = mkAuxUnit {
        modality = "image";
        inherit (cfg.image) artifact port;
        args = [
          "--served-model-name"
          "Qwen-Image-2.1"
        ];
        conflicts = textUnits;
      };
    }
    // lib.mapAttrs' (name: m: lib.nameValuePair "gufo-llm-${name}" (mkLlmUnit name m)) cfg.alternates;

    # The 27B Q8 remains a supported single-host alternate. Flash-Next Q8
    # was TP2-only and is retired with the canceled second host (#698).
    environment.etc."gufo/27b-q8-wanted.json".source =
      (pkgs.formats.json { }).generate "gufo-27b-q8-wanted.json"
        (
          modelStore.manifestFor [
            "qwen38-27b-q8-gguf"
            "qwen38-27b-dflash2-gguf"
          ]
        );

    environment.systemPackages = [
      cfg.package
      gufoSwitch
    ];

    networking.firewall.interfaces = lib.mkIf cfg.openLanPort {
      ${cfg.lanInterface}.allowedTCPPorts = [ cfg.port ];
    };
  };
}
