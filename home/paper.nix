{
  lib,
  osConfig,
  pkgs,
  ...
}:
# The paper loop's print half. The inbound half (Brother ADS-1800W
# scan-to-SFTP into ~/Paper/intake + the paper-intake collector/OCR
# pipeline) was REMOVED 2026-08-20: the scanner was returned to the shop.
# See git history for the retired units and pkgs/paper-intake's collector.
#
# Coordinator-only: the printer queue and the print skill live here.
let
  isCoordinator = osConfig.networking.hostName == "coordinator";
in
lib.mkIf isCoordinator {
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
