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
}
