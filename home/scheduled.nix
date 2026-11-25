{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
# Scheduled (AGENTS.md D52): the heartbeat, the one Nix-pure workflow.
# Tom, 2026-11-10: "the only nix pure workflow is the heartbeat. it gets
# a systemd timer unit." Each tick runs `scheduled tick`: it decodes the
# cron times of every agency's .agency/scheduled/*.jsonc, links one
# occurrence record per due item into the floor's inbox and, when a floor
# unit is named and records wait, starts that unit. It holds no floor
# logic: the floor's scheduled Source turns records into Triggers and the
# floor judges them. Runbook: docs/scheduled.md.
let
  scheduled = lib.getExe pkgs.scheduled;
  # The one shared value. The Master dsh profile was retired on
  # 2026-11-26 with dshd; the inbox stays at the path it had
  # (<the Master stateDir>/inbox/scheduled), now literal, so the records
  # already there are where the new floor's scheduled Source can be
  # pointed. tests/scheduled asserts the path.
  inbox = "${config.home.homeDirectory}/.agency/state/master/inbox/scheduled";
  # The systemd user unit a tick starts when records wait (pkgs/scheduled,
  # SCHEDULED_FLOOR_UNIT). null is the supported no-floor mode, chosen at
  # the 2026-11-26 dshd retirement: the tick links records and wakes nothing.
  # home/factory-floor.nix sets it once the factory floor is trusted to be
  # woken.
  floorUnit = null;
  floorDefault = lib.optionalString (
    floorUnit != null
  ) "--set-default SCHEDULED_FLOOR_UNIT ${lib.escapeShellArg floorUnit}";
  # Tom, Claude Code and the floor run the same program, and
  # `scheduled run` and `history` find the same inbox and floor. The
  # defaults live in the installed command: Home Manager's session
  # variables reach no NAS shell (useUserPackages puts hm-session-vars.sh
  # under /etc/profiles, which ~/.bash_profile does not source; a fish login reads
  # none), nor Herdr or Claude Code. A variable set by hand still wins.
  cli = pkgs.symlinkJoin {
    name = "scheduled-${pkgs.scheduled.version}";
    paths = [ pkgs.scheduled ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/scheduled \
        --set-default SCHEDULED_INBOX ${lib.escapeShellArg inbox} ${floorDefault}
    '';
    passthru = {
      unwrapped = pkgs.scheduled;
      inherit inbox floorUnit;
    };
    meta.mainProgram = "scheduled";
  };
in
# The heartbeat follows the brain role, never a floor: until the
# 2026-11-26 dshd retirement it was gated on the dshd module's enable.
lib.mkIf (osConfig.myFleet.has "brain") {
  home.packages = [ cli ];

  systemd.user.services.scheduled-heartbeat = {
    Unit = {
      Description = "Scheduled heartbeat: hand due occurrences to the floor";
      # A switch never kills a tick in flight; the next tick runs the
      # new generation (the paper-daemon-flush contract).
      X-RestartIfChanged = false;
      # The timer, run now and the panel all start this unit. A start
      # limit fails the timer itself (measured, home/paper.nix); a tick
      # is idempotent, so starts are unlimited.
      StartLimitIntervalSec = 0;
      # Commissioned when the master agency exists. Until then a tick
      # is skipped by this condition, never failed.
      ConditionPathIsDirectory = "%h/.agency";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${scheduled} tick";
      # systemctl, the one tool a wake calls, follows the running system,
      # never a login shell. No SCHEDULED_FLOOR_UNIT while floorUnit is null.
      Environment = [
        "PATH=/run/current-system/sw/bin"
        "SCHEDULED_INBOX=${inbox}"
      ]
      ++ lib.optional (floorUnit != null) "SCHEDULED_FLOOR_UNIT=${floorUnit}";
      # heartbeat.json, intake.json and .tick.lock: ~/.local/state/scheduled
      # ($STATE_DIRECTORY), never the floor's state dir.
      StateDirectory = "scheduled";
      # systemd's default is 0755; the files are 0600, keep their names private too.
      StateDirectoryMode = "0700";
      NoNewPrivileges = true;
      UMask = "0077";
      # The walk of ~ never competes with an interactive session for CPU
      # (home/harness-records.nix). A floor the tick wakes is its own unit
      # and keeps its own priority.
      Nice = 10;
      # Well past the tick lock's 60 s wait plus a wake (a --no-block
      # start returns at once), so systemd never kills a tick before it
      # logs why. Kept from the dshd era, when a wake waited up to 150 s.
      TimeoutStartSec = "5min";
    };
  };

  # No store path in this text: a new `scheduled` changes only the
  # service file, so fleet-update's active-unit gate passes the timer.
  systemd.user.timers.scheduled-heartbeat = {
    Unit.Description = "Scheduled heartbeat, hourly and after boot";
    Timer = {
      # Tom: "1h is a good midway between claude advertised 2-4 hrs
      # and openclaw 30min".
      OnCalendar = "hourly";
      # Linger starts the user manager at boot: one tick soon after a
      # power cut, even when no hour was missed.
      OnStartupSec = "2min";
      # A missed hour runs once at boot, never a backlog. Safe here: a
      # tick only decodes, links records and wakes.
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # The factory floor's panel on the Zenbook's loopback (docs/scheduled.md).
  # The port is the one the retired Master floor's dsh-web served on, kept
  # literal for the new floor's loopback panel (2026-11-26). Treat
  # the port as granting control equal to the owner's own shell: a floor
  # panel that takes no token lets any local process on the Zenbook steer
  # the floor through this forward. With nothing listening on the NAS the
  # forward is inert.
  # NAS-owned, like the live agency-web-client-tunnel; nothing of
  # Scheduled runs on the Zenbook. No store path in this text, so an
  # openssh bump never makes fleet-update hold a switch for it.
  systemd.user.services.scheduled-panel-tunnel =
    let
      # The factory floor's loopback panel port.
      webPort = "3082";
    in
    {
      Unit = {
        Description = "Factory floor panel: NAS loopback ${webPort} on the Zenbook";
        After = [ "network-online.target" ];
        StartLimitIntervalSec = 0;
      };
      Service = {
        ExecStart = lib.concatStringsSep " " [
          "/run/current-system/sw/bin/ssh -N -T -o BatchMode=yes"
          "-o HostName=100.121.160.100 -o HostKeyAlias=client"
          "-o ForwardAgent=no -o ControlMaster=no -o ControlPath=none"
          "-o ExitOnForwardFailure=yes -o ServerAliveInterval=30"
          "-o ServerAliveCountMax=3"
          "-R 127.0.0.1:${webPort}:127.0.0.1:${webPort} client"
        ];
        # The Zenbook sleeps and roams: retry quietly, forever.
        Restart = "always";
        RestartSec = "30s";
        UMask = "0077";
      };
      Install.WantedBy = [ "default.target" ];
    };
}
