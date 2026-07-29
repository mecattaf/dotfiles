{
  lib,
  pkgs,
  osConfig,
  ...
}:
# Nightly academic-OCR drain on the coordinator. Walks the NAS corpus
# work-list shortest-first through the paper-e2e mutation-ladder flow, one
# paper at a time, resuming per-paper via persisted flow-run-ids. The driver
# and work-list live in the appliance state root (~/.local/state/academic-ocr);
# this unit only provides the nightly cadence and the morning cutoff. The
# drain is idempotent — papers with a canonical receipt are skipped — so an
# overlapping manual run is safe (the driver holds a flock).
let
  hostName = osConfig.networking.hostName;
  stateRoot = "/home/tom/.local/state/academic-ocr";
in
{
  systemd.user.services.academic-drain = lib.mkIf (hostName == "coordinator") {
    Unit = {
      Description = "academic-ocr nightly corpus drain";
      # The NAS holds the source PDFs; without it the driver would burn its
      # consecutive-failure fuse on fetch errors.
      ConditionPathIsDirectory = "/mnt/nas/documents/academic-papers";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${stateRoot}/tools/drain.sh --stop-at 07:00";
      # A full night is the intended runtime; the stop-at wall clock is the
      # real bound, TimeoutStartSec just refuses to let a hung flow run past
      # breakfast.
      TimeoutStartSec = "11h";
    };
  };

  systemd.user.timers.academic-drain = lib.mkIf (hostName == "coordinator") {
    Unit.Description = "start the academic-ocr drain every night";
    Timer = {
      OnCalendar = "*-*-* 22:00:00";
      Persistent = false;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
