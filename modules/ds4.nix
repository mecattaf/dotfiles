{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ds4;
  catalog = import ../lib/local-models.nix { inherit lib; };
  store = import ../lib/model-store.nix { inherit catalog lib; };
  modelId = "deepseek-v41-flash-1017-q2-gguf";
  visionId = "deepseek-v41-flash-vision-gguf";
  draftId = "deepseek-v41-flash-dspark-gguf";
  tp2 = cfg.mode == "tp2";
  artifacts = [ modelId ] ++ lib.optional cfg.vision visionId ++ lib.optional cfg.dspark draftId;
  manifest = (pkgs.formats.json { }).generate "ds4-wanted.json" (store.manifestFor artifacts);
  containerPath =
    id: lib.replaceStrings [ store.runtimeRoot ] [ "/models" ] store.materialized.${id}.primary;
  rankArgs = [
    "--tensor-parallel"
    "--role"
    cfg.role
    "--transport"
    "tcp"
  ]
  ++ (
    if cfg.role == "coordinator" then
      [
        "--listen"
        cfg.coordinatorAddress
        (toString cfg.peerPort)
      ]
    else
      [
        "--coordinator"
        cfg.coordinatorAddress
        (toString cfg.peerPort)
      ]
  );
  # Single host (kyuz0's model card): the 340.6 GiB Q2 cannot be resident on
  # one 128 GB box, so ds4 streams routed experts from the local SSD through a
  # bounded expert cache. DSpark needs resident experts and is refused there.
  singleArgs = [
    "--ssd-streaming"
    "--ssd-streaming-cache-experts"
    cfg.ssdExpertCache
    "--batched-session"
    "1"
  ];
  serves = !tp2 || cfg.role == "coordinator";
  args = [
    (if serves then "ds4-server" else "ds4")
    "--rocm"
    "-m"
    (containerPath modelId)
    "--ctx"
    (toString cfg.context)
  ]
  ++ (if tp2 then rankArgs else singleArgs)
  ++ lib.optionals cfg.vision [
    "--vision"
    (containerPath visionId)
  ]
  ++ lib.optionals cfg.dspark [
    "--mtp-model"
    (containerPath draftId)
    "--dspark"
  ]
  ++ lib.optionals serves [
    "--host"
    cfg.apiAddress
    "--port"
    (toString cfg.port)
  ];
  check = pkgs.writeShellScript "ds4-preflight" ''
    set -eu
    # Image acquisition is an explicit preparation transaction, never startup.
    ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg cfg.image}
    ${lib.concatMapStringsSep "\n" (
      id:
      lib.concatMapStringsSep "\n" (f: ''
        p=${lib.escapeShellArg "${store.runtimeRoot}/${id}/${f.name}"}
        if [ ! -f "$p" ] || [ "$(${pkgs.coreutils}/bin/stat -c %s "$p")" != ${toString f.bytes} ]; then
          echo "ds4: missing/wrong-size ${id}/${f.name}; explicitly acquire on NAS and borrow with /etc/ds4/wanted.json" >&2
          exit 1
        fi
      '') store.materialized.${id}.files
    ) artifacts}
  '';
in
{
  options.services.ds4 = {
    enable = lib.mkEnableOption "the hand-started kyuz0 DeepSeek V4.1 server (a TP rank or one host)";
    mode = lib.mkOption {
      type = lib.types.enum [
        "tp2"
        "single-ssd"
      ];
      default = "tp2";
      description = ''
        `tp2`: one resident tensor-parallel rank per Strix (both hosts keep the
        full Q2 locally). `single-ssd`: this host alone serves the model with
        SSD expert streaming; `role`, the peer and DSpark do not apply.
      '';
    };
    ssdExpertCache = lib.mkOption {
      type = lib.types.strMatching "[1-9][0-9]*(GB)?";
      default = "76GB";
      description = "single-ssd: the routed-expert cache (`--ssd-streaming-cache-experts`), a count or <n>GB; kyuz0 tested 76GB on a 128 GB Framework Desktop.";
    };
    image = lib.mkOption {
      type = lib.types.strMatching "[^[:space:]]+@sha256:[a-f0-9]{64}";
      default = "docker.io/kyuz0/strix-halo-ds4-toolbox@sha256:34dec90acfba046123ec35b849db9db0aad7491284b6534b05b11a8f1b5f7d1c";
      description = "Immutable official ROCm 10 image; 2026-10-23 build uses kyuz0/ds4 abf18415738337da0de0e2b463567711548ea5ec. Pull explicitly before startup.";
    };
    role = lib.mkOption {
      type = lib.types.enum [
        "coordinator"
        "worker"
      ];
      default = "coordinator";
    };
    coordinatorAddress = lib.mkOption {
      type = lib.types.strMatching "([0-9]{1,3}\\.){3}[0-9]{1,3}";
      default = "10.42.0.2";
    };
    peerAddress = lib.mkOption {
      type = lib.types.strMatching "([0-9]{1,3}\\.){3}[0-9]{1,3}";
      default = "10.42.0.5";
    };
    apiAddress = lib.mkOption {
      type = lib.types.strMatching "([0-9]{1,3}\\.){3}[0-9]{1,3}";
      default = cfg.coordinatorAddress;
      defaultText = lib.literalExpression "config.services.ds4.coordinatorAddress";
      description = "Where the OpenAI-compatible API listens: the TP coordinator, or the single-ssd host's own LAN address.";
    };
    interface = lib.mkOption {
      type = lib.types.str;
      default = "enp191s0";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8732;
    };
    peerPort = lib.mkOption {
      type = lib.types.port;
      default = 9911;
    };
    context = lib.mkOption {
      type = lib.types.ints.positive;
      default = 32768;
    };
    # Off until the 1017 vision encoder is proven to load in the pinned image.
    vision = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    dspark = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    wanted = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Add ds4's artifacts (the Q2, plus vision and DSpark when on) to this
        host's services.local-models.artifacts, so a default
        `local-models-borrow` loans them and `local-models-prune` keeps them.
        Turn it off on a host that declares ds4 but cannot hold its files.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.myFleet.has "compute";
        message = "ds4 belongs on Strix compute hosts, never the NAS brain.";
      }
      {
        assertion = cfg.port != cfg.peerPort && cfg.port != config.services.gufo.port;
        message = "ds4 inference, peer and Gufo API ports must be distinct.";
      }
      {
        assertion = tp2 || !cfg.dspark;
        message = "ds4 single-ssd streams experts from disk; DSpark needs them resident (services.ds4.dspark = false).";
      }
    ];
    virtualisation.podman.enable = true;
    # The host that runs ds4 wants its files: they join the host wanted set
    # (/etc/local-models/wanted.json), which is prune's keep set, so prune
    # never lists a ds4 loan there. /etc/ds4/wanted.json stays as the scoped
    # manifest for borrowing only ds4's files. Neither moves a byte; never put
    # weights in Nix. Ordered last, so a fresh default borrow lands the
    # resident Gufo model before 340 GiB of DeepSeek.
    services.local-models.artifacts = lib.mkIf cfg.wanted (lib.mkAfter artifacts);
    environment.etc."ds4/wanted.json".source = manifest;
    systemd.services.ds4 = {
      description =
        if tp2 then
          "DeepSeek V4.1 Flash 1017 TP ${cfg.role} (attended, TCP)"
        else
          "DeepSeek V4.1 Flash 1017 single host, SSD expert streaming (attended)";
      wantedBy = [ ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      conflicts = [
        "gufo-llm.service"
        "gufo-tp2.service"
        "gufo-image.service"
      ]
      ++ map (name: "gufo-llm-${name}.service") (builtins.attrNames config.services.gufo.alternates);
      serviceConfig = {
        Type = "simple";
        ExecStartPre = check;
        ExecStart = lib.escapeShellArgs (
          [
            "${pkgs.podman}/bin/podman"
            "run"
            "--rm"
            "--pull=never"
            "--name=ds4-fleet"
            "--network=host"
            "--ipc=private"
            "--device=/dev/kfd"
            "--device=/dev/dri"
            "--ulimit=memlock=-1"
            "--cap-drop=ALL"
            "--security-opt=no-new-privileges"
            "--read-only"
            "--tmpfs=/tmp:rw,size=1g"
            "--volume=${store.runtimeRoot}:/models:ro"
            cfg.image
          ]
          ++ args
        );
        ExecStop = "${pkgs.podman}/bin/podman stop --time=90 ds4-fleet";
        TimeoutStartSec = "45min";
        TimeoutStopSec = "2min";
        Restart = "no";
        LimitMEMLOCK = "infinity";
        MemoryHigh = "108G";
        MemoryMax = "116G";
        MemorySwapMax = 0;
      };
    };
    # API has no application auth. Only NAS/client can reach the TP
    # coordinator, and only the NAS (dsh) a single-ssd host; the peer link
    # accepts only the other compute host over wired Ethernet.
    networking.firewall.extraInputRules =
      if tp2 then
        ''
          iifname "${cfg.interface}" ip saddr ${cfg.peerAddress} tcp dport ${toString cfg.peerPort} accept
        ''
        + lib.optionalString (cfg.role == "coordinator") ''
          iifname "${cfg.interface}" ip saddr { 10.42.0.1, 10.42.0.16 } tcp dport ${toString cfg.port} accept
        ''
      else
        ''
          iifname "${cfg.interface}" ip saddr 10.42.0.1 tcp dport ${toString cfg.port} accept
        '';
  };
}
