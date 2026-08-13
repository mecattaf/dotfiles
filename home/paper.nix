{
  lib,
  osConfig,
  pkgs,
  ...
}:
# The paper loop's inbound half (dotfiles scanning plane, 2026-08-13).
#
# ~/Paper/intake is the flat drop directory the Brother ADS-1800W pushes
# into (scan-to-SFTP) and eSCL pull scripts write to. A path unit fires the
# collector on activity; a low-frequency timer sweeps anything the path
# unit's run left unsettled (files younger than the settle window survive
# a collect pass untouched, and a path unit only re-fires on the NEXT
# change). The collector queues one tally job per batch; tally owns
# execution and proof, exactly like call diarization.
#
# Coordinator-only: the scanner lives with the coordinator, and the
# processor needs its llama-swap OCR lane.
let
  isCoordinator = osConfig.networking.hostName == "coordinator";
in
lib.mkIf isCoordinator {
  home.packages = [ pkgs.paper-intake ];

  systemd.user.services.paper-intake-collect = {
    Unit.Description = "Sweep settled scans from ~/Paper/intake into a tally job";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.paper-intake}/bin/paper-intake-collect";
    };
  };

  systemd.user.paths.paper-intake-collect = {
    Unit.Description = "Watch ~/Paper/intake for arriving scans";
    Path = {
      PathChanged = "%h/Paper/intake";
      MakeDirectory = true;
    };
    Install.WantedBy = [ "paths.target" ];
  };

  systemd.user.timers.paper-intake-collect = {
    Unit.Description = "Sweep ~/Paper/intake for scans the path unit left settling";
    Timer = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # Printing quiet hours: between 00:00 and 06:00 print-auto renders but
  # spools physical submission into ~/Paper/outbox (one JSON entry per
  # job); this timer flushes the outbox to CUPS at 06:05. Persistent
  # catches a machine that was asleep at flush time, and the flusher
  # itself refuses to run inside the window, so an early catch-up run
  # cannot print at night. "/print force" bypasses the spool entirely at
  # submission time and never involves this unit.
  systemd.user.services.paper-print-flush = {
    Unit.Description = "Flush spooled print jobs from ~/Paper/outbox to CUPS";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.paper-intake}/bin/paper-print-flush";
    };
  };

  systemd.user.timers.paper-print-flush = {
    Unit.Description = "Morning flush of the print outbox (quiet hours end)";
    Timer = {
      OnCalendar = "*-*-* 06:05:00";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
