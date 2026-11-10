{
  lib,
  osConfig,
  pkgs,
  ...
}:
# Scheduled (AGENTS.md D52): the heartbeat, the one Nix-pure workflow.
# Tom, 2026-11-10: "the only nix pure workflow is the heartbeat. it gets
# a systemd timer unit." Each tick runs `scheduled tick`: it decodes the
# cron times of every agency's .agency/workflows/*.jsonc, hands the due
# occurrences to the factory floor and wakes the floor. The work is
# impure and lives on the floor (the superagent fork in the dsh
# config), never here. Runbook: docs/scheduled.md.
let
  scheduled = lib.getExe pkgs.scheduled;
in
lib.mkIf osConfig.dshd.enable {
  # Tom, Claude Code and the dsh-web panel run the same program.
  home.packages = [ pkgs.scheduled ];

  systemd.user.services.scheduled-heartbeat = {
    Unit = {
      Description = "Scheduled heartbeat: decode due work, wake the floor";
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
      Environment = [ "PATH=/run/current-system/sw/bin" ];
      NoNewPrivileges = true;
      UMask = "0077";
      # Longer than dshd's startupTimeout (150 s) for a floor start.
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
      # hands off and wakes.
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
