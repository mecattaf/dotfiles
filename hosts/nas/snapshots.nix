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
# COST, stated honestly: a snapshot is a metadata write of a second or two —
# nothing on RAM or CPU — but every run wakes the disk, which is real friction
# against the spin-down design (#130 convention 2). Cadence history, all on
# day one-and-two: hourly (default) → daily noon (Tom: "too intense") →
# MONTHLY, first Saturday 08:00 (Tom's ruling 2026-08-21 afternoon: "NAS
# items genuinely don't get updated that often … this buys me nothing
# honestly, let's not overbuild"). The media trees are near-static and the
# real protection is the redundancy stack — RAID 1 mirror (coming), monthly
# LaCie cold dump, borg (ws2b) — so the snapshot tier is a light convenience,
# not a load-bearing layer. 08:00 keeps it clear of the overnight
# update-center build window (Tom asked for "after the nightly build
# finishes composing"; 2am risked landing mid-build on this slow CPU) and
# the disk is usually awake by then anyway. Oops window: up to a month —
# accepted explicitly.
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
        # First Saturday of the month (a day-of-month range ANDs with the
        # weekday in systemd calendar syntax), 08:00 — see the COST paragraph.
        onCalendar = "Sat *-*-1..7 08:00:00";
        settings = {
          # ISO-ish suffixes, so `btrbk.photos.20260803T1500` sorts lexically
          # and reads unambiguously in `ls`.
          timestamp_format = "long";
          # Local snapshots only — no send/receive target. The off-box copies
          # are borg (ws2b) and the LaCie (ws3), both of which have their own
          # schedule and their own failure modes.
          snapshot_preserve_min = "latest";
          # Twelve monthlies — one year of restore points at monthly cadence
          # (the hourly and daily tiers died with their cadences, see COST).
          # Snapshots of mostly-static media are nearly free — only changed
          # extents are pinned.
          snapshot_preserve = "12m";
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
