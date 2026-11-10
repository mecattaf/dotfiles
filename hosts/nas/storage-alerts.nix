{
  config,
  lib,
  pkgs,
  ...
}:
# ─── NAS storage alerts (O1 PR-1, 2026-11-10) ───────────────────────────────
# Per-mount usage tripwires plus one mount-presence tripwire, all through
# ../../modules/tripwire.nix: one timer and one root oneshot each, every 10 min.
# A fire writes a marker into the failure-marker channel
# (../../modules/failure-surfacing.nix), which fish prints once at the next
# interactive login, the channel coredumps and unit failures already use. A
# condition that stays true re-marks every 24 h (renotifySeconds), so a disk
# that stays full is not reported once and then forgotten.
#
# Why per mount: the eMMC root reached 97% on 2026-11-05 with nothing watching
# it. What filled it was not the system (1-2G): it was the pre-cutover home
# hidden under the /home mount (20.9G), /tmp (up to 24G) and /var (7.4G). The
# trip points differ by what each disk is for, and each re-arms 5 points lower:
#
#   /            eMMC root      75%  interim; 25% once /var and /tmp have left
#                                    the eMMC (O1 phase 3). Holding only /etc,
#                                    /root and the host identity, growth there
#                                    is a leak, not a capacity question.
#   /boot        eMMC ESP       80%  three generations of kernels and initrds.
#   /mnt/fast    1TB pool       85%  one btrfs for @home, @fast (/nix, attic,
#                                    the remote journal); btrfs degrades near full.
#   /mnt/immich  256GB SSD      85%  PostgreSQL dies on ENOSPC.
#   /mnt/nas     4TB HDD        92%  85% on 2026-11-10: the next real capacity fill.
#
# Why presence: every data mount here is `nofail`, so a missing one does not
# stop the boot; its writers land in the eMMC directory underneath instead.
# The empty skeleton dirs found on the eMMC under /mnt/immich and /mnt/nas on
# 2026-11-10 are exactly that. Every declared fileSystems entry except / is
# required. The usage tripwire of an absent mount reports 0 (df would describe
# the eMMC), so nas-mounts reports an absence once rather than twice.
#
# Cost: statfs and /proc/self/mountinfo only. Neither reads the HDD, so the
# 10-minute polls never wake it from the smartd `-n standby` spin-down.
let
  cfg = config.myNas.storageAlerts;
  markerDir = config.myFailureSurfacing.markerDir;

  mountPoints = lib.mapAttrsToList (_: fs: fs.mountPoint) config.fileSystems;
  autoMounts = lib.mapAttrsToList (_: fs: fs.mountPoint) (
    lib.filterAttrs (_: fs: !(lib.elem "noauto" fs.options)) config.fileSystems
  );
  required = lib.unique cfg.requiredMounts;

  # Markers are written under the reconciler's lock, as the journal watchers
  # do. Their first line starts with a date, never "<unit> failed", so
  # failure-marker-reconcile leaves them alone: they are event markers.
  lockMarkers = ''
    dir="''${FAILURE_MARKER_DIR:?FAILURE_MARKER_DIR must be set}"
    install -d -m 0755 "$dir"
    exec 9>"$dir/.failure-marker-reconcile.lock"
    flock 9
  '';

  usage =
    {
      name,
      mount,
      what,
      threshold,
      hint ? null,
    }:
    {
      enable = lib.elem mount mountPoints;
      description = "disk usage of the ${what} (${mount})";
      intervalSeconds = 600;
      onBootSec = "5min";
      inherit threshold;
      rearm = threshold - 5;
      comparison = "ge";
      renotifySeconds = 86400;
      valueField = "DISK_USED_PCT";
      environment.FAILURE_MARKER_DIR = markerDir;
      sensorPath = [
        pkgs.coreutils
        pkgs.util-linux
      ];
      sensor = ''
        m=${lib.escapeShellArg mount}
        if ! mountpoint -q "$m"; then
          echo "0 unmounted:${name}"
          exit 0
        fi
        pct="$(df --output=pcent "$m" | tail -n 1 | tr -dc '0-9')"
        [ -n "$pct" ]
        echo "$pct disk:${name}"
      '';
      onFirePath = [
        pkgs.coreutils
        pkgs.util-linux
      ];
      onFire = ''
        ${lockMarkers}
        marker="$dir/disk-${name}"
        {
          printf '%s  %s %s is %s%% full (alert at %s%%, episode %s)\n' \
            "$(date '+%Y-%m-%d %H:%M')" ${lib.escapeShellArg what} ${lib.escapeShellArg mount} "$1" "$3" "$4"
          printf '  check: df -h %s; sudo du -xh --max-depth=2 %s | sort -h | tail\n' \
            ${lib.escapeShellArg mount} ${lib.escapeShellArg mount}
          ${lib.optionalString (hint != null) "printf '  %s\\n' ${lib.escapeShellArg hint}"}
        } > "$marker"
        chmod 0644 "$marker"
      '';
    };
in
{
  options.myNas.storageAlerts = {
    rootThreshold = lib.mkOption {
      type = lib.types.ints.between 10 95;
      default = 75;
      description = ''
        Percent used on the eMMC root at which tripwire-disk-root fires. 75 is
        interim: set it to 25 once /var and /tmp have left the eMMC and their
        hidden copies are reclaimed (O1 phase 3).
      '';
    };
    requiredMounts = lib.mkOption {
      type = with lib.types; listOf str;
      description = ''
        Mount points tripwire-nas-mounts requires to be mounted. This module
        defines every auto-mounted fileSystems entry except /; other modules
        may add more.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = required != [ ] && lib.all (lib.hasPrefix "/") required;
        message = "myNas.storageAlerts.requiredMounts must be a non-empty list of absolute paths.";
      }
    ];

    myNas.storageAlerts.requiredMounts = lib.filter (m: m != "/") autoMounts;

    myTripwire = {
      disk-root = usage {
        name = "root";
        mount = "/";
        what = "eMMC root";
        threshold = cfg.rootThreshold;
        hint = "du cannot see files hidden under a mount point: bind-mount / elsewhere and du there (O1 section 3.1)";
      };
      disk-boot = usage {
        name = "boot";
        mount = "/boot";
        what = "eMMC ESP";
        threshold = 80;
      };
      disk-pool = usage {
        name = "pool";
        mount = "/mnt/fast";
        what = "1TB pool (/home, /nix, /mnt/fast)";
        threshold = 85;
      };
      disk-immich = usage {
        name = "immich";
        mount = config.myNas.immichDisk.mountPoint;
        what = "256GB Immich SSD";
        threshold = 85;
      };
      disk-hdd = usage {
        name = "hdd";
        mount = "/mnt/nas";
        what = "4TB HDD";
        threshold = 92;
      };

      nas-mounts = {
        description = "required NAS mounts are present";
        intervalSeconds = 600;
        onBootSec = "5min";
        threshold = 1;
        # Re-arms on the first poll with nothing missing. (rearm = 0 would
        # never re-arm a "ge" tripwire whose healthy sample is 0.)
        rearm = 1;
        comparison = "ge";
        renotifySeconds = 86400;
        valueField = "MOUNTS_MISSING";
        environment.FAILURE_MARKER_DIR = markerDir;
        sensorPath = [ pkgs.util-linux ];
        sensor = ''
          n=0
          for m in ${lib.escapeShellArgs required}; do
            mountpoint -q "$m" || n=$((n + 1))
          done
          echo "$n mounts"
        '';
        onFirePath = [
          pkgs.coreutils
          pkgs.util-linux
        ];
        onFire = ''
          missing=""
          for m in ${lib.escapeShellArgs required}; do
            mountpoint -q "$m" || missing="$missing $m"
          done
          ${lockMarkers}
          marker="$dir/nas-mounts"
          {
            printf '%s  %s required mount(s) missing:%s (episode %s)\n' \
              "$(date '+%Y-%m-%d %H:%M')" "$1" "''${missing:- none at marker time}" "$4"
            printf '  their writers land on the eMMC root meanwhile; check: findmnt%s; systemctl --failed\n' \
              "$missing"
          } > "$marker"
          chmod 0644 "$marker"
        '';
      };
    };
  };
}
