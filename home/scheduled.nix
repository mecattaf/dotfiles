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
# occurrence record per due item into the superagent's inbox and starts
# the floor when records wait. It holds no superagent logic: the floor's
# scheduled Source turns records into Triggers and the main Session
# judges them. Runbook: docs/scheduled.md.
let
  scheduled = lib.getExe pkgs.scheduled;
  # The one shared value: the floor's scheduled Source reads
  # <stateDir>/inbox/scheduled by default, beside orchestrator.sqlite.
  # programs.dsh.master.stateDir (home/dsh-master.nix) is what the Master
  # profile renders as dsh-superagent's stateDir; tests/scheduled asserts
  # the two agree.
  inbox = "${config.programs.dsh.master.stateDir}/inbox/scheduled";
  # The floor's dshd instance; the name the Master floor recipe keeps.
  floorInstance = "floor";
  # Tom, Claude Code and the dsh-web panel run the same program, and
  # `scheduled run` and `history` find the same inbox and floor. The
  # defaults live in the installed command: Home Manager's session
  # variables reach no NAS shell (useUserPackages puts hm-session-vars.sh
  # under /etc/profiles, which ~/.bash_profile does not source), nor Herdr
  # or Claude Code. A variable set by hand still wins.
  cli = pkgs.symlinkJoin {
    name = "scheduled-${pkgs.scheduled.version}";
    paths = [ pkgs.scheduled ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/scheduled \
        --set-default SCHEDULED_INBOX ${lib.escapeShellArg inbox} \
        --set-default SCHEDULED_FLOOR_INSTANCE ${floorInstance}
    '';
    passthru = {
      unwrapped = pkgs.scheduled;
      inherit inbox floorInstance;
    };
    meta.mainProgram = "scheduled";
  };
in
lib.mkIf osConfig.dshd.enable {
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
      # dshd and what it calls (nix-store, systemctl, journalctl)
      # follow the running system, never a login shell.
      Environment = [
        "PATH=/run/current-system/sw/bin"
        "SCHEDULED_INBOX=${inbox}"
        "SCHEDULED_FLOOR_INSTANCE=${floorInstance}"
      ];
      # heartbeat.json, intake.json and .tick.lock: ~/.local/state/scheduled
      # ($STATE_DIRECTORY), never the superagent's stateDir.
      StateDirectory = "scheduled";
      NoNewPrivileges = true;
      UMask = "0077";
      # The walk of ~ never competes with an interactive session for CPU
      # (home/harness-records.nix). The floor dshd starts is its own unit
      # and keeps its own priority.
      Nice = 10;
      # Longer than dshd's startupTimeout (150 s) plus the tick lock's
      # 60 s wait, so systemd never kills a tick before it logs why.
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
      # A missed hour runs once at boot, never a backlog. Safe here,
      # unlike update-center's Persistent=false: a tick only decodes,
      # links records and wakes.
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # The Scheduled panel on the Zenbook's loopback (docs/scheduled.md).
  # NAS-owned, like the live agency-web-client-tunnel; nothing of
  # Scheduled runs on the Zenbook. No store path in this text, so an
  # openssh bump never makes fleet-update hold a switch for it.
  systemd.user.services.scheduled-panel-tunnel = {
    Unit = {
      Description = "Scheduled panel: NAS loopback 3082 on the Zenbook";
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
        "-R 127.0.0.1:3082:127.0.0.1:3082 client"
      ];
      # The Zenbook sleeps and roams: retry quietly, forever.
      Restart = "always";
      RestartSec = "30s";
      UMask = "0077";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
