{
  config,
  pkgs,
  ...
}:
# ─── strix disk floor (2026-11-25) ──────────────────────────────────────────
# strix-coordinator is the fleet's only Nix builder. The house rule is to stop
# any build when `df -h /` shows less than 25 GB free; on 2026-11-25 the root
# was at 126 GB free before a 63 GB GC of stale roots. This tripwire fires at
# 50 GiB available on /, twice the build floor, so there is room to clean
# before builds have to stop. It re-arms at 60 GiB and re-marks every 24 h
# while the disk stays low. A fire writes a marker into the failure-marker
# channel (../../modules/failure-surfacing.nix); nothing is deleted.
#
# /tmp on this host holds build clones and scratch checkouts that are meant to
# be pushed or bundled; it is emptied at every boot from here on.
let
  markerDir = config.myFailureSurfacing.markerDir;
  floorGiB = 50;
in
{
  boot.tmp.cleanOnBoot = true;

  myTripwire.disk-floor = {
    description = "free space on the strix root (/)";
    intervalSeconds = 600;
    onBootSec = "5min";
    threshold = floorGiB;
    rearm = floorGiB + 10;
    comparison = "le";
    renotifySeconds = 86400;
    valueField = "DISK_AVAIL_GIB";
    environment.FAILURE_MARKER_DIR = markerDir;
    sensorPath = [ pkgs.coreutils ];
    sensor = ''
      avail="$(df --output=avail -B1G / | tail -n 1 | tr -dc '0-9')"
      [ -n "$avail" ]
      echo "$avail disk:root"
    '';
    onFirePath = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    onFire = ''
      dir="''${FAILURE_MARKER_DIR:?FAILURE_MARKER_DIR must be set}"
      install -d -m 0755 "$dir"
      exec 9>"$dir/.failure-marker-reconcile.lock"
      flock 9
      marker="$dir/disk-floor"
      {
        printf '%s  strix root / has %s GiB free (alert at %s GiB; builds stop below 25 GB; episode %s)\n' \
          "$(date '+%Y-%m-%d %H:%M')" "$1" "$3" "$4"
        printf '  check: df -h /; sudo du -xh --max-depth=2 / | sort -h | tail; ls -l /nix/var/nix/gcroots/auto | wc -l\n'
      } > "$marker"
      chmod 0644 "$marker"
    '';
  };
}
