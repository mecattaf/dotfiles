{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# Gufo: the fleet's local inference engine on the strix, replacing Halogen
# (dotfiles #525). Tom, 2026-10-13: "i said let  move to gufo!! not
# halogen!!!!" and "use that as the full collection of modles that we use".
#
# Upstream is github:gufo-org/gufo (flake input `gufo`, pinned in flake.nix):
# one native `gufo` binary for gfx1151 with the model graphs, tokenizers and
# HIP kernels compiled in. No container. Each `gufo serve <modality>` process
# loads exactly ONE model, so this module runs one systemd unit per model:
#
#   gufo-llm.service          the resident text model (Flash-Next), at boot
#                             when autoStart, on the fleet address and port
#   gufo-llm-<name>.service   an alternate text model (the 27B, DeepSeek V4
#                             Flash), started only by `gufo-switch <name>`
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
# one large model owns the GPU. Halogen is no longer declared.
let
  cfg = config.services.gufo;
  tp = cfg.tp2;
  catalog = import ../lib/local-models.nix { inherit lib; };
  modelStore = import ../lib/model-store.nix { inherit catalog lib; };

  dirOf = id: modelStore.materialized.${id}.directory;
  primaryOf = id: modelStore.materialized.${id}.primary;

  # Every file of the named artifacts present at its catalog size, or a clear
  # refusal naming the borrow command. Same contract as Halogen's bundleCheck.
  bundleCheckFor =
    ids:
    pkgs.writeShellScript "gufo-bundle-check" ''
      set -eu
      fail=0
      ${lib.concatMapStringsSep "\n" (
        id:
        lib.concatMapStringsSep "\n" (f: ''
          p=${lib.escapeShellArg "${dirOf id}/${f.name}"}
          if [ ! -r "$p" ] || [ "$(${pkgs.coreutils}/bin/stat -c %s "$p")" != ${toString f.bytes} ]; then
            echo "gufo: missing or wrong size: $p (want ${toString f.bytes} bytes); run: sudo local-models-borrow --yes" >&2
            fail=1
          fi
        '') modelStore.materialized.${id}.files
      ) ids}
      exit "$fail"
    '';

  # Startup returns only once the model answers, so `systemctl start` and
  # `gufo-switch` report a usable server, not a process that is still loading.
  waitReady =
    port:
    pkgs.writeShellScript "gufo-wait-ready" ''
      until ${pkgs.curl}/bin/curl -fsS -o /dev/null "http://127.0.0.1:${toString port}/ready"; do
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

  alternateNames = builtins.attrNames cfg.alternates;
  unitOf = name: if name == "flash" then "gufo-llm.service" else "gufo-llm-${name}.service";
  textUnits = map unitOf ([ "flash" ] ++ alternateNames) ++ lib.optional tp.enable "gufo-tp2.service";

  tp2Args =
    llmArgs (cfg.llm // { servedModelName = tp.modelName; })
    ++ [
      "--tp-world-size"
      "2"
      "--tp-rank"
      (toString tp.rank)
      "--tp-bootstrap-port"
      (toString tp.bootstrapPort)
      "--tp-control-port"
      (toString tp.controlPort)
      "--tp-rdma-device"
      tp.rdmaDevice
      "--tp-gid-index"
      (toString tp.gidIndex)
    ]
    ++ lib.optionals (tp.rank == 1) [
      "--tp-bootstrap-host"
      tp.peerAddress
    ];

  # Upstream only accepts --tp-control-token in argv. LoadCredential keeps it
  # out of the Nix store and unit text; /proc/<pid>/cmdline still exposes it.
  tp2Start = pkgs.writeShellScript "gufo-tp2-start" ''
    set -eu
    token="$(cat "$CREDENTIALS_DIRECTORY/control-token")"
    if [ -z "$token" ] || [ "''${#token}" -gt 4096 ]; then
      echo "gufo-tp2: control token must contain 1..4096 bytes" >&2
      exit 1
    fi
    exec ${
      lib.escapeShellArgs ([ (lib.getExe' tp.package "gufo") ] ++ tp2Args)
    } --tp-control-token "$token"
  '';

  tp2WaitActive = pkgs.writeShellScript "gufo-tp2-wait-active" ''
    set -eu
    state=${lib.escapeShellArg "/sys/class/infiniband/${tp.rdmaDevice}/ports/1/state"}
    deadline=$((SECONDS + 300))
    until [ -r "$state" ] && ${pkgs.gnugrep}/bin/grep -Eq '^4:[[:space:]]+ACTIVE[[:space:]]*$' "$state"; do
      if [ "$SECONDS" -ge "$deadline" ]; then
        echo "gufo-tp2: RDMA port did not become ACTIVE within 300 seconds: $state" >&2
        exit 1
      fi
      sleep 1
    done
  '';

  # Carry forward 352eac88 / #257's measured 100 us budget. Zero left only
  # POLL and burned ~70 W idle on the old twins. Keep the held fd in a small
  # root companion; the GPU process stays an unprivileged DynamicUser.
  tp2LatencyHold = pkgs.writeShellScript "gufo-tp2-latency-hold" ''
    set -eu
    exec 3> /dev/cpu_dma_latency
    v=${toString tp.cpuDmaLatencyUs}
    printf '%b' "$(printf '\\0%03o' \
      $((v & 255)) $(((v >> 8) & 255)) $(((v >> 16) & 255)) $(((v >> 24) & 255)))" >&3
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';

  mkLlmUnit = name: m: {
    description = "Gufo text model ${m.servedModelName} (${m.artifact})";
    conflicts = (lib.remove (unitOf name) textUnits) ++ [ "gufo-image.service" ];
    wantedBy = lib.optionals (name == "flash" && cfg.autoStart) [ "multi-user.target" ];
    serviceConfig = gpuServiceConfig // {
      MemoryHigh = "96G";
      MemoryMax = "104G";
      MemorySwapMax = 0;
      ExecStartPre = "${bundleCheckFor (artifactsOf m)}";
      ExecStart = lib.escapeShellArgs ([ (lib.getExe' cfg.package "gufo") ] ++ llmArgs m);
      ExecStartPost = "${waitReady cfg.port}";
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
      inherit conflicts;
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
        ExecStartPost = "${waitReady port}";
      };
    };

  gufoSwitch = pkgs.writeShellApplication {
    name = "gufo-switch";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      choice=''${1:-}
      case "$choice" in
        ${lib.concatStringsSep " | " ([ "flash" ] ++ alternateNames ++ [ "off" ])}) ;;
        *)
          echo "usage: gufo-switch <${
            lib.concatStringsSep "|" ([ "flash" ] ++ alternateNames ++ [ "off" ])
          }>" >&2
          echo "Stops whichever Gufo text model is resident and starts the named one (a cold load: minutes); off stops them all." >&2
          exit 64
          ;;
      esac
      case "$choice" in
        flash) unit=gufo-llm.service ;;
        off) unit= ;;
        *) unit="gufo-llm-$choice.service" ;;
      esac
      for u in ${lib.escapeShellArgs textUnits}; do
        [ "$u" = "$unit" ] || systemctl stop "$u"
      done
      [ -n "$unit" ] || exit 0
      systemctl start "$unit"
      systemctl show "$unit" --property=Id,ActiveState,SubState,ActiveEnterTimestamp
    '';
  };
in
{
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
      description = "Whether the resident text model (gufo-llm) starts at boot.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Listen address of the text server; the firewall below decides who reaches it.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8731;
      description = "The text server's port: Halogen's, so callers keep their URL across the cutover.";
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
      description = "The resident text model (gufo-llm.service).";
    };

    alternates = lib.mkOption {
      type = lib.types.attrsOf llmType;
      default = { };
      description = ''
        Other text models, one unit each (gufo-llm-<name>.service), on the
        same port, never resident together with the primary or each other.
        Only `gufo-switch <name>` starts one; `gufo-switch flash` goes back.
      '';
    };

    tp2 = lib.mkOption {
      default = { };
      description = "Two-host Flash-Next over USB4 RDMA. Declares gufo-tp2.service, with no boot target.";
      type = lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "the on-demand Gufo TP2 rank";
          package = lib.mkOption {
            type = lib.types.package;
            default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.gufo-rdma;
            defaultText = lib.literalExpression "inputs.self.packages.x86_64-linux.gufo-rdma";
          };
          rank = lib.mkOption {
            type = lib.types.enum [
              0
              1
            ];
            default = 0;
          };
          peerAddress = lib.mkOption {
            type = lib.types.strMatching "([0-9]{1,3}\\.){3}[0-9]{1,3}";
            default = "127.0.0.1";
            description = "Peer's wired LAN IPv4 address for bootstrap/control and firewall admission.";
          };
          bootstrapPort = lib.mkOption {
            type = lib.types.port;
            default = 18515;
          };
          controlPort = lib.mkOption {
            type = lib.types.port;
            default = 18516;
          };
          rdmaDevice = lib.mkOption {
            type = lib.types.strMatching "[a-zA-Z0-9_-]+";
            default = "usb4_rdma0";
          };
          gidIndex = lib.mkOption {
            type = lib.types.ints.between (-1) 255;
            default = -1;
            description = "-1 lets Gufo select a usable GID; verify at hardware qualification.";
          };
          cpuDmaLatencyUs = lib.mkOption {
            type = lib.types.nullOr (lib.types.ints.between 1 2147483647);
            default = 100;
            description = "Positive PM QoS budget held on both hosts only while TP2 runs; null disables the hold. Zero (POLL-only on the old twins) is forbidden. Requalify latency/power on 7.3.";
          };
          modelName = lib.mkOption {
            type = lib.types.str;
            default = cfg.llm.servedModelName;
            defaultText = lib.literalExpression "config.services.gufo.llm.servedModelName";
            description = "Exact served id; TP2 shares services.gufo.llm's Flash-Next bundle and loading arguments on both ranks.";
          };
          tokenFile = lib.mkOption {
            type = lib.types.str;
            default = "/run/agenix/gufo-tp2-control-token";
            description = "Shared agenix token, read with LoadCredential; never a Nix-store plaintext.";
          };
        };
      };
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
    assertions = [
      {
        # The resident model only. An alternate whose artifacts this host does
        # not want yet (DeepSeek V4 Flash until explicitly borrowed) is
        # refused at start by its bundle check, which names the borrow command.
        assertion = lib.all (a: lib.elem a config.services.local-models.artifacts) (artifactsOf cfg.llm);
        message = "The resident Gufo model's artifacts (services.gufo.llm) must be in this host's services.local-models.artifacts.";
      }
      {
        assertion = !(cfg.alternates ? flash) && !(cfg.alternates ? off);
        message = "services.gufo.alternates may not be named `flash` (the primary) or `off` (gufo-switch's stop verb).";
      }
      {
        assertion =
          !tp.enable || (tp.bootstrapPort != tp.controlPort && cfg.llm.artifact == "qwen38-flash-next-gguf");
        message = "Gufo TP2 requires distinct bootstrap/control ports and the Flash-Next bundle (the fork only supports qwen4exp TP2).";
      }
    ];

    systemd.services = {
      gufo-tp2-latency = lib.mkIf (tp.enable && tp.cpuDmaLatencyUs != null) {
        description = "Gufo TP2 CPU DMA latency budget (${toString tp.cpuDmaLatencyUs} us)";
        wantedBy = [ ];
        partOf = [ "gufo-tp2.service" ];
        unitConfig.StopWhenUnneeded = true;
        serviceConfig = {
          Type = "exec";
          ExecStart = "${tp2LatencyHold}";
          Restart = "on-failure";
          RestartSec = "5s";
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
          CapabilityBoundingSet = "";
          DevicePolicy = "closed";
          DeviceAllow = [ "/dev/cpu_dma_latency rw" ];
        };
      };
      gufo-tp2 = lib.mkIf tp.enable {
        description = "Gufo TP2 rank ${toString tp.rank}, USB4 RDMA (on demand)";
        wantedBy = [ ];
        requires = lib.optional (tp.cpuDmaLatencyUs != null) "gufo-tp2-latency.service";
        wants = [
          "network-online.target"
          "thunderbolt-ibverbs-check.service"
        ];
        after = [
          "network-online.target"
          "thunderbolt-ibverbs-check.service"
        ]
        ++ lib.optional (tp.cpuDmaLatencyUs != null) "gufo-tp2-latency.service";
        conflicts = (lib.remove "gufo-tp2.service" textUnits) ++ [ "gufo-image.service" ];
        serviceConfig =
          gpuServiceConfig
          // {
            Restart = "always";
            MemoryHigh = "96G";
            MemoryMax = "104G";
            MemorySwapMax = 0;
            LoadCredential = [ "control-token:${tp.tokenFile}" ];
            ExecStartPre = [
              "${bundleCheckFor (artifactsOf cfg.llm)}"
              "${tp2WaitActive}"
            ];
            ExecStart = "${tp2Start}";
          }
          // lib.optionalAttrs (tp.rank == 0) {
            ExecStartPost = "${waitReady cfg.port}";
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

      # 31 GiB of BF16 weights do not fit beside Flash-Next or DeepSeek V4
      # Flash, so it takes the GPU from every text unit while it runs.
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

    environment.systemPackages = [
      cfg.package
      gufoSwitch
    ];

    networking.firewall.interfaces = lib.mkIf cfg.openLanPort {
      ${cfg.lanInterface}.allowedTCPPorts = [ cfg.port ];
    };

    # TP2's control sockets bind all addresses upstream. Admit only the peer
    # over Ethernet, never an unrestricted port or a USB4 IP interface.
    networking.nftables.enable = lib.mkIf tp.enable true;
    networking.firewall.extraInputRules = lib.mkIf tp.enable ''
      iifname "${cfg.lanInterface}" ip saddr ${tp.peerAddress} tcp dport { ${toString tp.bootstrapPort}, ${toString tp.controlPort} } accept
    '';
  };
}
