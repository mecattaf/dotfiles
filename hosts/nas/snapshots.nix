{ config, lib, ... }:
# ─── #130 ws2a: local point-in-time snapshots of the data subvolumes ────────
#
# Btrfs snapshots are the cheap half of "Time Machine semantics": instant,
# near-free, and they make an oops ("I deleted the wrong folder", "the scanner
# rewrote every tag") a copy-out rather than a restore-from-backup. They are NOT
# a backup — they live on the same disk as the data they snapshot and die with
# it. The actual backup is #130 ws2b (borg, ./backups.nix) and the disaster copy
# is the quarterly LaCie mirror (./lacie-mirror.nix). All three, on purpose.
#
# The subvolume layout this needs ALREADY EXISTS — photos / music / documents /
# videos / services / .snapshots were created as real subvolumes by the Day-2
# runbook (see the layout comment block in ./storage.nix), which is exactly the
# "cheap now, expensive later" decision #130 flagged. Nothing to migrate.
#
# ── Why .snapshots is safe from the NFS client, verified against storage.nix ──
# services.nfs.server.exports lists SIX entries: the /mnt/nas root (fsid=0) and
# one explicit fsid per exported subvolume (photos 1, music 2, documents 3,
# services 4, videos 5). `.snapshots` has NO entry and never gets one. Under
# NFSv4 each Btrfs subvolume is its own st_dev, and nfsd will not cross into a
# subvolume that lacks its own export entry — a client that walks into
# /mnt/nas/.snapshots sees an empty directory. That is the whole containment
# story, and it is why the per-subvolume export list in storage.nix is written
# out longhand instead of relying on a single fsid=0 root export. The snapshots
# btrbk creates below are themselves nested subvolumes INSIDE .snapshots, so
# they are two boundaries away from anything the coordinator can reach.
#
# RUNBOOK — enable
#   1. Confirm the layout is real, not directories (this is the one thing that
#      would make snapshots silently no-op):
#        btrfs subvolume list /mnt/nas
#      Expect photos, music, documents, videos, services, .snapshots.
#   2. hosts/nas/default.nix: myNas.snapshots.enable = true; deploy.
#   3. Dry-run before trusting the schedule:
#        btrbk -c /etc/btrbk/nas.conf dryrun
#        systemctl start btrbk-nas.service && btrbk -c /etc/btrbk/nas.conf list snapshots
#   4. Prove containment from the COORDINATOR, once:
#        ls /mnt/nas/.snapshots     # must be empty or ENOENT, never a listing
#   5. Restore drill (do it once so you know it works before you need it):
#        cp -a --reflink=auto /mnt/nas/.snapshots/photos.<ts>/some/file /mnt/nas/photos/
#      Reflink copies are free within the filesystem. To roll a whole subvolume
#      back, snapshot the live one aside first, then `btrfs subvolume snapshot`
#      the archived one into place — never `btrfs subvolume delete` the live
#      subvolume while Immich/Navidrome/Plex hold open files in it.
#
# COST, stated honestly: hourly snapshots wake the disk ~24x/day for a metadata
# write of a second or two. That is real friction against the spin-down design
# (#130 convention 2) and it is the first knob to turn if the drive never seems
# to park — `onCalendar = "*:0/6"` (every 6h) with `6h` retention keeps the
# shape and cuts the wakes to 4/day. Started at hourly because "I overwrote it
# an hour ago" is the case snapshots exist for.
let
  cfg = config.myNas.snapshots;
  storageRoot = "/mnt/nas";
in
{
  options.myNas.snapshots.enable = lib.mkEnableOption "btrbk hourly/daily/monthly snapshots of the NAS data subvolumes (#130 ws2a)";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.myNas.storage.enable;
        message = "myNas.snapshots requires the verified myNas.storage mount";
      }
    ];

    services.btrbk = {
      # A snapshot run must never outrank a media stream on the same spindle.
      niceness = 15;
      ioSchedulingClass = "idle";
      instances.nas = {
        onCalendar = "hourly";
        settings = {
          # ISO-ish suffixes, so `btrbk.photos.20260803T1500` sorts lexically
          # and reads unambiguously in `ls`.
          timestamp_format = "long";
          # Local snapshots only — no send/receive target. The off-box copies
          # are borg (ws2b) and the LaCie (ws3), both of which have their own
          # schedule and their own failure modes.
          snapshot_preserve_min = "latest";
          # #130's stated retention: hourly for a day, daily for a month,
          # monthly for a year. Snapshots of mostly-static media are nearly
          # free — only changed extents are pinned — so the cost of the long
          # tail is small and the budget line in #130 allows 200 GB for it.
          snapshot_preserve = "24h 30d 12m";
          volume.${storageRoot} = {
            # Relative to the volume: /mnt/nas/.snapshots, the never-exported
            # subvolume described in the comment block above.
            snapshot_dir = ".snapshots";
            subvolume = {
              photos = { };
              music = { };
              documents = { };
              videos = { };
              # `services` is deliberately NOT snapshotted. It holds live Plex
              # SQLite state (regenerable by a library rescan), the journal
              # archive (already an archive, and append-only), and
              # navidrome-backups (backups of a thing whose live state is on
              # the NVMe). Snapshotting it would pin churn without protecting
              # anything irreplaceable. The DB that DOES matter — Immich's
              # PostgreSQL — is not here at all: it lives on /mnt/fast and is
              # protected by the nightly pg_dump into photos/backups/db, which
              # rides the photos snapshots above.
            };
          };
        };
      };
    };

    # btrbk's own timer is the schedule; the unit must not start before the
    # subvolumes it snapshots are actually mounted.
    systemd.services.btrbk-nas.unitConfig.RequiresMountsFor = [ storageRoot ];
  };
}
