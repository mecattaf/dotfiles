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
      # NO ConditionPathIsDirectory on the NAS corpus here (#154). The corpus
      # is still a hard precondition — without it the driver would burn its
      # consecutive-failure fuse on fetch errors — but a *start condition* is
      # the one way to state it that cannot recover: an unmet condition makes
      # systemd skip the job, and a job that never started is never restarted,
      # so a reboot that beat the /mnt/nas automount left the drain dead until
      # a human noticed (2026-08-05, 2h). drain.sh now waits for the corpus
      # itself and exits 69 when it stays absent, which Restart=always retries
      # on the RestartSec cadence until the NAS comes back.
    };
    Service = {
      ExecStart = "${drainPkg}/bin/academic-drain";
      # Covers every exit: work-list dry, stop-at, the failure fuse, and the
      # corpus-absent exit 69 that replaced the start condition.
      Restart = "always";
      # Pause between passes once the work-list is dry (or after the
      # 3-consecutive-failure fuse) instead of spinning. A cold automount is
      # absorbed by drain.sh's own 300s wait, so this cadence only ever paces
      # the genuinely-NAS-down case.
      RestartSec = 600;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
