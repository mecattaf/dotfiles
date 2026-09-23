{
  config,
  options,
  lib,
  pkgs,
  ...
}:
# substrate-link: the NAS side of the Cloudflare floor (Substrate) to ax link, declared and OFF.
#
# DESIGN: ~/today/evals-2026-09-23/link/LINK-DESIGN.md (2026-09-23), BUILD.md beside it. CODE: vendored
# in pkgs/substrate-link/src from ax-conwip eval/2026-09-23-link a021003 apps/link (pkgs/substrate-link/SYNC.md).
# Formerly conwip-link; renamed with the ax-conwip project (now "substrate", Tom 2026-09-23 E10). DATE: 2026-09-23.
# Critique items carried here: N1 (axServer from ax-fleet), N2 (Node 24, pkgs), N3 (guest URL), N4 (floorUrls).
#
# WHAT IT IS. One long-running process that dials OUT to the floor (a Durable Object behind a
# Cloudflare Worker), leases AgentJobs under the floor's CONWIP cap, creates one ax Task per lease
# (GetTask, then UpdateTask only on NotFound: ax has no CreateTask and UpdateTask is a blind upsert),
# watches the Tasks by ListTasks, and reports each verdict through a write-ahead outbox. Nothing
# dials in: no tunnel, no listener, no port opened in this file.
#
# WHY A SYSTEM UNIT ON THE NAS HOST AND NOT A POD. The link needs no Kubernetes API (ax is gRPC), it
# must keep reporting "ax is down" to the floor while k3s is down, its journal must outlive the
# cluster, and its bearer must never become a Kubernetes Secret: ax-controller's ClusterRole reads
# secrets cluster-wide (ax-fleet DESIGN section 9). ax-server's ClusterIP answers host processes on
# a k3s node through kube-proxy, the same path the coordinator's socket proxy uses (DESIGN D13).
#
# THE TOKEN IS A PATH, NEVER A VALUE. agenix decrypts floor-link-token.age for root only (0400);
# LoadCredential hands the unit a private copy under $CREDENTIALS_DIRECTORY. The program reads it
# once and never logs it. Minting the token (a Worker secret and this age file) is Tom's hand.
#
# THE GATE. `enable` defaults to false and nothing in this repository sets it. Arming needs, in
# order: the ax-fleet PR switched on the NAS, the sealed token, the floor URL, a guest Complete
# relay (completion = guest on zero-patch ax), and Tom's ack. Exit 78 (bad token or config) stops the
# restart loop; exit 75 (a second replica holds the session, or an endpoint switch to a URL in
# floorUrls was persisted) retries after RestartSec.
let
  cfg = config.myNas.substrateLink;
  inherit (lib) mkEnableOption mkIf mkOption types;
  # N1: one source for ax-server's address. When modules/ax-fleet is imported its pinned ClusterIP wins.
  axFleetIP = if options ? myAxFleet && options.myAxFleet ? axServerClusterIP then config.myAxFleet.axServerClusterIP else null;
  # N3 (critique A5): a guest must post to a fleet-internal relay, never to a public Workers host.
  publicWorkersHost = u: lib.hasInfix ".workers.dev" u || lib.hasInfix ".pages.dev" u;
  # Review round 2: mirrors isFleetInternalUrl (apps/link/src/link.ts). Private ranges match only IPv4 literals
  # (10.evil.example and 127.0.0.1.nip.io are names), names only under .internal/.lan/.local/.home.arpa, IPv6 only
  # ::1 and ULA, a single label only when listed in internalHosts. Stricter than the program where they differ.
  hostOf = u: let m = builtins.match "[a-z]+://([^@/]*@)?(\\[[^]]*]|[^/:?#]+).*" (lib.toLower u); in if m == null then "" else builtins.elemAt m 1;
  ipv4Of = h: builtins.match "([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})" h;
  privateV4 = o: let a = lib.toInt (builtins.elemAt o 0); b = lib.toInt (builtins.elemAt o 1); in
    a == 127 || a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31) || (a == 100 && b >= 64 && b <= 127);
  fleetInternalUrl = u: let h = hostOf u; o = ipv4Of h; in
    if o != null then privateV4 o
    else if lib.hasPrefix "[" h then h == "[::1]" || builtins.match "\\[f[cd][0-9a-f]{2}:.*" h != null
    else h == "localhost" || lib.elem h cfg.internalHosts || builtins.match "([a-z0-9-]+\\.)+(internal|lan|local|home\\.arpa)" h != null;
in
{
  options.myNas.substrateLink = {
    enable = mkEnableOption "the Substrate floor-to-ax link (outbound only). OFF; see this file's header before flipping it";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../../pkgs/substrate-link { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../pkgs/substrate-link { }";
      description = "The link program, built from the source vendored in pkgs/substrate-link/src.";
    };

    floorUrl = mkOption {
      type = types.str;
      default = "";
      example = "https://substrate.example.dev";
      description = "The floor Worker's base URL. HTTPS only; the link appends /rpc.";
    };

    floorUrls = mkOption {
      type = types.listOf types.str;
      default = [ cfg.floorUrl ];
      defaultText = lib.literalExpression "[ config.myNas.substrateLink.floorUrl ]";
      description = "N4 (B18): the only floor URLs a Lease `endpoint` may move this link to, exact https matches. The switch is persisted in the state directory and the unit restarts onto it (exit 75).";
    };

    holder = mkOption {
      type = types.str;
      default = "nas-link-1";
      description = "holderIdentity. The floor binds it to this link's token; one session per identity.";
    };

    axServer = mkOption {
      type = types.str;
      default = if axFleetIP != null then "${axFleetIP}:8080" else "10.201.0.80:8080";
      defaultText = lib.literalExpression ''"''${config.myAxFleet.axServerClusterIP}:8080" when modules/ax-fleet is imported, else "10.201.0.80:8080"'';
      description = "ax-server as host:port (gRPC h2c, no auth upstream, #376). N1: read from ax-fleet's axServerClusterIP option (D13).";
    };

    atespace = mkOption {
      type = types.str;
      default = "fleet";
    };

    image = mkOption {
      type = types.str;
      default = "ax-agent";
      example = "localhost:5000/ax-agent@sha256:0000";
      description = "Task image; set it to the digest ax-fleet-image-ref prints.";
    };

    gateway = mkOption {
      type = types.str;
      default = "halogen";
      description = "The egress Gateway every Task names. A missing Gateway means open egress on v0.3.0, so the link leases nothing while GetGateway answers NotFound or the Gateway allows * (B10).";
    };

    maxInFlight = mkOption {
      type = types.ints.positive;
      default = 2;
      description = "Sandbox cap this link fills: the ateom-gvisor WorkerPool replicas (ax-fleet section 9).";
    };

    servedLabels = mkOption {
      type = types.listOf types.str;
      default = [
        "seat:halogen"
        "runtime:gvisor"
      ];
      description = "runs-on labels this link accepts. Claude seats stay on the coordinator until Tom rules (W6).";
    };

    seatCommands = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = {
        halogen = [
          "ax-agent"
          "pi"
        ];
      };
      description = "Task command per seat (the ax-agent adapter's modes, ax-fleet section 10.2).";
    };

    completion = mkOption {
      type = types.enum [
        "auto"
        "p1"
        "guest"
      ];
      # The fleet runs stock ax with no P1 (pkgs/ax: patches = [ ]), so "p1" and "auto" lease
      # nothing (B6). "guest" is the only mode that completes on this fleet; it needs guestCompleteUrl,
      # a fleet-internal relay that does not exist yet, so arming fails its assertion until then.
      default = "guest";
      description = "p1: the controller writes the outcome (carried patch P1); the link probes GetTaskResult at start and whenever ax comes back, and leases nothing on a server without P1 (B6). auto: the same, never guest. guest: the L7 reserve, pre-P1, the guest completes with a per-lease token through a fleet-internal relay.";
    };

    guestCompleteUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Only for completion = guest: the fleet-internal URL the guest posts its per-lease Complete to (N3: never a workers.dev host).";
    };

    internalHosts = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Review round 2: single-label host names a guestCompleteUrl may use (fleet DNS names without a dot).";
    };

    tokenAgeFile = mkOption {
      type = types.path;
      default = ../../secrets/floor-link-token.age;
      defaultText = lib.literalExpression "../../secrets/floor-link-token.age";
      description = "The sealed per-link bearer (secrets.nix: editors ++ nasOnly). Evaluated only when enabled.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasPrefix "https://" cfg.floorUrl;
        message = "myNas.substrateLink.floorUrl must be an https:// URL (the bearer never travels in clear).";
      }
      {
        assertion = config.networking.hostName == "nas";
        message = "substrate-link runs on the hypervisor host only (placement ruling: NAS = k3s server, Substrate, ax-server).";
      }
      {
        assertion = cfg.completion != "guest" || (cfg.guestCompleteUrl != null && !(publicWorkersHost cfg.guestCompleteUrl) && fleetInternalUrl cfg.guestCompleteUrl);
        message = "completion = guest needs a fleet-internal guestCompleteUrl: a private IPv4 literal, ::1 or ULA, or a name under .internal/.lan/.local/.home.arpa, never a workers.dev or pages.dev host (critique A5, review round 2).";
      }
      {
        assertion = lib.all (u: lib.hasPrefix "https://" u) cfg.floorUrls && lib.elem cfg.floorUrl cfg.floorUrls;
        message = "myNas.substrateLink.floorUrls must be https:// URLs and include floorUrl.";
      }
    ];

    age.secrets.floor-link-token = {
      file = cfg.tokenAgeFile;
      mode = "0400";
    };

    systemd.services.substrate-link = {
      description = "substrate-link: Cloudflare floor to ax, outbound only";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "k3s.service"
      ];
      environment = {
        LINK_FLOOR_URL = cfg.floorUrl;
        LINK_FLOOR_URLS = lib.concatStringsSep "," cfg.floorUrls;
        LINK_HOLDER = cfg.holder;
        AX_SERVER = cfg.axServer;
        AX_ATESPACE = cfg.atespace;
        LINK_IMAGE = cfg.image;
        LINK_GATEWAY = cfg.gateway;
        LINK_MAX_IN_FLIGHT = toString cfg.maxInFlight;
        LINK_SERVED_LABELS = lib.concatStringsSep "," cfg.servedLabels;
        LINK_SEAT_COMMANDS = builtins.toJSON cfg.seatCommands;
        LINK_COMPLETION = cfg.completion;
        LINK_INTERNAL_HOSTS = lib.concatStringsSep "," cfg.internalHosts;
      }
      // lib.optionalAttrs (cfg.guestCompleteUrl != null) { LINK_GUEST_COMPLETE_URL = cfg.guestCompleteUrl; };
      serviceConfig = {
        ExecStart = lib.getExe cfg.package;
        DynamicUser = true;
        StateDirectory = "substrate-link"; # journal.jsonl, session-id, floor-endpoint; a few fsynced lines per job
        StateDirectoryMode = "0700";
        LoadCredential = [ "floor-link-token:${config.age.secrets.floor-link-token.path}" ];
        Restart = "on-failure";
        RestartSec = "10s";
        RestartPreventExitStatus = [ 78 ];
        TimeoutStopSec = "30s"; # SIGTERM drains: no new leases, outbox flushed; ax Tasks keep running
        UMask = "0077";
        MemoryMax = "512M";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        # MemoryDenyWriteExecute stays off: V8's JIT needs writable and executable pages.
      };
    };
  };
}
