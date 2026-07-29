{
  inputs,
  lib,
  pkgs,
  osConfig,
  ...
}:
# Always-on academic-OCR drain on the coordinator (ruled 24/7, 2026-07-29):
# walks the NAS corpus work-list all-Bocconi-first through the paper-e2e
# mutation-ladder flow, one paper at a time, resuming per-paper via persisted
# flow-run-ids, then absorbs finished papers into the notes repo as its
# epilogue. GPU nodes hold coordinator-gpu at low priority, so interactive
# work and the thermal tripwire preempt between pages; a night-window revert
# is one ExecStart flag (--stop-at HH:MM) plus a timer.
#
# Code ships from the store (pkgs/academic-ocr-drain); all mutable state
# stays in ~/.local/state/academic-ocr. The drain is idempotent (receipted
# papers skip; flock refuses overlap), so Restart=always is safe: when the
# corpus is fully drained each restart is a cheap no-op scan.
let
  hostName = osConfig.networking.hostName;
  drainPkg = pkgs.callPackage ../pkgs/academic-ocr-drain {
    tally = inputs.tally.packages.${pkgs.stdenv.hostPlatform.system}.tally;
  };
in
{
  home.packages = lib.optionals (hostName == "coordinator") [ drainPkg ];

  systemd.user.services.academic-drain = lib.mkIf (hostName == "coordinator") {
    Unit = {
      Description = "academic-ocr corpus drain (24/7, low-priority GPU)";
      # The NAS holds the source PDFs; without it the driver would burn its
      # consecutive-failure fuse on fetch errors.
      ConditionPathIsDirectory = "/mnt/nas/documents/academic-papers";
    };
    Service = {
      ExecStart = "${drainPkg}/bin/academic-drain";
      Restart = "always";
      # Pause between passes once the work-list is dry (or after the
      # 3-consecutive-failure fuse) instead of spinning.
      RestartSec = 600;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
