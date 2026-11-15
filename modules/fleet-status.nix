{
  config,
  lib,
  pkgs,
  ...
}:
# ─── fleet-status: the graded per-host collector, and the fan-out view ──────
#
# Issue #356, 2026-09-13. Every host gets `fleet-status-collect` plus
# /etc/fleet-status/profile.json, which says what that host is EXPECTED to
# have. The profile is what separates `missing-by-design` from `unknown`:
# a brain with Home Manager expects a user manager, including the NAS.
# Each brain also gets `fleet-status` and
# /etc/fleet-status/hosts.json, and it fans the collector out as
# `ssh root@<name>` over the mesh (modules/mesh.nix already authorizes tom's
# key for root on every host). The optional NAS observation service below
# adds no timer, agent scheduler or database.
# DECISIONS.md 2026-09-13 records why.
#
# Roles come from the configuration, not from hostnames, so a moved service
# moves its facts with it:
#   gufo    services.gufo.enable            → llama-swap/gufo-llm*, /running, /v1/models
#   (runs, the Tally planes, went with the Tally sunset on 2026-09-30)
#   attention  the Herdr server host (home/herdr.nix gates its unit on
#              myFleet.has "brain", and so does this module; the
#              flake's herdr-oom-isolation check pins that shape)
# The profile NAME is still per host, because it names the expectation set in
# the terminal view. An unlisted hostname fails evaluation instead of quietly
# shipping as "unprofiled".
let
  host = config.networking.hostName;

  profileNames = {
    strix-coordinator = "strix-compute";
    strix-worker = "strix-compute";

    nas = "appliance";
    client = "thin-client";
  };

  # The fan-out order is the reading order of the view: the desk first, then
  # the inference box, the appliance and the laptop, which may be asleep.
  # A dormant host (modules/mesh-registry.nix) is left out of the view.
  order = lib.filter config.myFleet.active [
    "strix-coordinator"
    "strix-worker"

    "nas"
    "client"
  ];

  registry = import ./mesh-registry.nix;

  enabled = name: config.services.${name}.enable or false;

  roles =
    lib.optional (enabled "gufo") "gufo" ++ lib.optional (config.myFleet.has "brain") "attention";

  profile = {
    name = profileNames.${host} or "unprofiled";
    # The user manager is expected wherever Home Manager gives tom a session.
    # The NAS uses its own release-26.05 Home Manager input.
    user_manager = config ? home-manager;
    inherit roles;
    gufo_port = config.services.gufo.port or 8731;
    # Declared mounts are checked against the live mount table.
    # noauto/automount mounts may legitimately be absent.
    mounts = lib.mapAttrsToList (_: fs: {
      mountpoint = fs.mountPoint;
      on_demand = lib.elem "noauto" fs.options || lib.elem "x-systemd.automount" fs.options;
    }) config.fileSystems;
  };

  hosts = map (name: {
    inherit name;
    profile = profileNames.${name};
    target = "root@${builtins.head registry.${name}.aliases}";
    # Every node, the strix included, is collected as root over ssh.
    # A local run as tom cannot read root-only state, and it would grade
    # the strix through a different code path (no runuser) than the other
# three.
# tom → root@strix is authorized by the mesh (MEASURED 2026-09-13:
    # `ssh -o BatchMode=yes root@strix id -u` → 0). If the strix's
    # sshd is broken, the view reads it UNREACHABLE, which is the truth.
    transport = "ssh";
  }) order;

  collectOnly = pkgs.runCommand "fleet-status-collect" { } ''
    mkdir -p "$out/bin"
    ln -s ${pkgs.fleet-status}/bin/fleet-status-collect "$out/bin/fleet-status-collect"
  '';

  isDashboard = config.myFleet.has "brain";
  observer = config.services.fleet-status.observer;
  observerConfig = pkgs.writeText "fleet-observer.json" (builtins.toJSON {
    fleetCommand = [ "${pkgs.fleet-status}/bin/fleet-status" "--json" ];
    dshdCommand = [ "/run/current-system/sw/bin/dshd" "ls" "--json" ];
    # The normal seats helper remains the only slow account acquisition owner.
    # It may use its cache and read native usage endpoints; it sends no prompts.
    seatsCommand = [ "/home/tom/.local/bin/seats" "--json" "--only" "cc,cc2,codex,openrouter" "--no-spend" "--cache-ttl" "1800" ];
    systemctlCommand = [ "systemctl" "--user" "show" "dshd@*.service" "--property=Id,CPUUsageNSec,MemoryCurrent,MemoryPeak,TasksCurrent,IOReadBytes,IOWriteBytes,NRestarts" ];
    journalCommand = [
      "journalctl" "--user" "--follow" "--output=json" "--no-pager" "--user-unit=dshd@*.service"
      "MESSAGE_ID=39f53479d3a045ac8e11786248231fbf"
      "MESSAGE_ID=9d1aaa27d60140bd96365438aad20286"
      "MESSAGE_ID=be02cf6855d2428ba40df7e9d022f03d"
      "MESSAGE_ID=d9b373ed55a64feb8242e02dbe79a49c"
    ];
    dshSessions = "/home/tom/.dsh/sessions";
    laneMeter = "/home/tom/.local/state/seats/lane-usage.jsonl";
    python = "${pkgs.python3}/bin/python3";
    intervals = { hosts = 300; metrics = 60; instances = 60; seats = 600; tails = 10; cloudflareQuota = 3600; vercelQuota = 3600; };
    cloudflareQuota = if config.age.secrets ? cloudflare-account-id && config.age.secrets ? cloudflare-api-token then {
      accountFile = config.age.secrets.cloudflare-account-id.path;
      tokenFile = config.age.secrets.cloudflare-api-token.path;
      includedDailyNeurons = 10000;
    } else null;
    vercelQuota = if config.age.secrets ? vercel-ai-gateway-key-1 then { tokenFile = config.age.secrets.vercel-ai-gateway-key-1.path; } else null;
    metricsCommands = {
      nas = [ "${pkgs.fleet-status}/bin/fleet-status-metrics" ];
      # Qualified fixed APU device; only reads counters while runtime-PM is
      # active. No model load, broad sensor discovery, SMART or HDD command.
      strix-coordinator = [ "${pkgs.openssh}/bin/ssh" "-o" "BatchMode=yes" "-o" "ConnectTimeout=3" "strix-coordinator" "${pkgs.fleet-status}/bin/fleet-status-metrics" "--gpu-device" "/sys/bus/pci/devices/0000:c2:00.0" ];
    };
    inherit (observer) publishUrl publishTokenFile;
  });
in
{
  options.services.fleet-status.observer = {
    enable = lib.mkOption { type = lib.types.bool; default = isDashboard; description = "Keep one lightweight passive fleet observer on the agent host."; };
    publishUrl = lib.mkOption { type = lib.types.str; default = ""; description = "Optional HTTPS-only fixed public snapshot publisher origin."; };
    publishTokenFile = lib.mkOption { type = lib.types.str; default = ""; description = "NAS-only publisher credential file; no token value in Nix or argv."; };
  };
  config = {
  assertions = [
    {
      assertion = profileNames ? ${host};
      message = "modules/fleet-status.nix: host `${host}` has no fleet-status profile; add it to profileNames.";
    }
    {
      assertion = lib.all (n: registry ? ${n}) order;
      message = "modules/fleet-status.nix: every fan-out host must be in modules/mesh-registry.nix.";
    }
  ];

  environment.etc."fleet-status/profile.json".text = builtins.toJSON profile;
  environment.etc."fleet-status/hosts.json" = lib.mkIf isDashboard {
    text = builtins.toJSON hosts;
  };
  environment.etc."fleet-status/observer.json" = lib.mkIf (isDashboard && observer.enable) {
    source = observerConfig;
  };

  environment.systemPackages = [ (if isDashboard then pkgs.fleet-status else collectOnly) ];
  home-manager.users.tom.systemd.user.services.fleet-observer = lib.mkIf (isDashboard && observer.enable) {
    Unit = { Description = "Passive fleet and provider observation owner"; After = [ "network-online.target" ]; };
    Service = {
      ExecStart = "${pkgs.fleet-status}/bin/fleet-observer --config ${observerConfig}";
      Restart = "on-failure";
      RestartSec = 15;
      KillMode = "mixed";
      TimeoutStopSec = 60;
      UMask = "0077";
      Nice = 10;
      MemoryMax = "256M";
      Environment = [ "PATH=/home/tom/.local/bin:/etc/profiles/per-user/tom/bin:/run/current-system/sw/bin" ];
    };
    Install.WantedBy = [ "default.target" ];
  };
  };
}
