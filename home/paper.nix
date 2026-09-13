{
  lib,
  osConfig,
  pkgs,
  ...
}:
# The paper loop (dotfiles#384). "/print" is one file write: an agent drops
# ~/Paper/intake/<slug>.md and paper-daemon owns everything after it —
# render, target_pages validation, quiet hours, the pinned-queue guard, and a
# receipt only when the PRINTER reports every impression. The layout under
# ~/Paper is the daemon's: intake/ (drops), outbox/ (held for 06:05),
# printed/<id>/receipt.json, rejected/<id>/, failed/<id>/, work/ (in flight).
# ~/Paper/inbox/ is NOT this loop's: it is the Huion's (DECISIONS 2026-09-13).
#
# Coordinator-only: the printer queue and the print skill live here.
let
  isCoordinator = osConfig.networking.hostName == "coordinator";
  daemon = lib.getExe pkgs.paper-daemon;
in
lib.mkIf isCoordinator {
  # PathChanged, not PathExistsGlob/DirectoryNotEmpty: those re-trigger in a
  # loop while anything sits in the directory, and intake/ legitimately keeps
  # a subdirectory (.adopted-2026-09-09/) the daemon ignores. PathChanged
  # fires on the rename that completes a drop; a drop that lands while a job
  # is being watched is picked up by the run's own re-scan, and the sweep
  # below is the backstop for anything else.
  systemd.user.paths.paper-daemon = {
    Unit.Description = "Watch ~/Paper/intake for print drops";
    Path = {
      PathChanged = "%h/Paper/intake";
      MakeDirectory = true;
      Unit = "paper-daemon.service";
    };
    Install.WantedBy = [ "paths.target" ];
  };

  systemd.user.services.paper-daemon = {
    Unit = {
      Description = "Print loop: render, validate and submit ~/Paper/intake drops";
      # A switch must never kill a job the daemon is watching over IPP: the
      # sheets are already moving, and a restart would leave work/<id>/
      # stranded with no receipt. The next path event or sweep runs the new
      # generation.
      X-RestartIfChanged = false;
      # No start rate limit. One drop is several inotify events (the .tmp
      # create, its close-write, the rename), and a start while the oneshot
      # is still active merges, so a few drops in a row are easily five
      # starts in ten seconds. MEASURED 2026-09-13 with a transient
      # PathChanged unit on this box: the sixth start leaves the SERVICE
      # start-limit-hit and the PATH unit failed with unit-start-limit-hit,
      # and it never watches again, even after the window passes, until
      # someone resets it. With StartLimitIntervalSec=0 the same twelve rapid
      # triggers all ran and the path stayed active. Nothing here can loop
      # by itself: only an outside write or the sweep starts a run.
      StartLimitIntervalSec = 0;
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${daemon} run";
      # Serial jobs, each allowed 120 s + 20 s/page at the printer.
      TimeoutStartSec = "6h";
    };
  };

  systemd.user.timers.paper-daemon-sweep = {
    Unit.Description = "Backstop sweep of ~/Paper/intake every five minutes";
    Timer = {
      OnCalendar = "*:0/5";
      Unit = "paper-daemon.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # Quiet hours end. Persistent catches a machine that was asleep at 06:05;
  # the flush itself refuses to run inside 00:00–06:00, so an early catch-up
  # cannot print at night. Drops with `force: true` never wait here.
  systemd.user.services.paper-daemon-flush = {
    Unit = {
      Description = "Morning flush of the print outbox (quiet hours end)";
      X-RestartIfChanged = false;
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${daemon} flush";
      TimeoutStartSec = "6h";
    };
  };

  systemd.user.timers.paper-daemon-flush = {
    Unit.Description = "Morning flush of the print outbox (quiet hours end)";
    Timer = {
      OnCalendar = "*-*-* 06:05:00";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
