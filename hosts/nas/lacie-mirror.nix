{ lib, pkgs, ... }:
# Cold-storage dump (Tom's ruling 2026-08-21, superseding the 2026-08-02
# bisync ruling): the LaCie 4TB lives unplugged in a drawer; roughly once a
# month — or slower; the cadence is entirely whenever Tom plugs it in — it
# goes into a NAS USB port and the NAS dumps everything that changed ONE WAY,
# NAS -> LaCie. Plug in, wait for the unit to finish, unplug.
# That plug event IS the trigger: udev matches the LaCie's Btrfs UUID (pinned
# since the 2026-07-23 NTFS->Btrfs migration) and starts the service. The
# mount point is /mnt/lacie — never /mnt/nas (#131).
#
# One-way, deliberately: with the clouds gone the NAS is the sole master and
# the LaCie is pure redundancy against a catastrophic drive failure. Nothing
# that happens to the drawer drive may ever flow back. And because a sync
# faithfully propagates *deletions* too, anything removed or overwritten on
# the NAS is parked under /mnt/lacie/.previous-versions/<date>/ instead of
# vanishing from the only cold copy — an oops on the NAS costs one plug-in to
# undo, not the data. Prune that directory by hand when the drive fills.
let
  lacieUuid = "20e38790-a639-4ffc-8f1a-3921d1aedb97";

  mirror = pkgs.writeShellScript "lacie-mirror" ''
    set -u
    export PATH=${
      lib.makeBinPath [
        pkgs.util-linux
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnugrep
        pkgs.rclone
      ]
    }
    mkdir -p /mnt/lacie /var/lib/lacie-mirror
    # Local-path sync needs no real config, but without HOME rclone hunts
    # for one (and threatens to drop rclone.conf in the CWD). Pin it.
    export RCLONE_CONFIG=/var/lib/lacie-mirror/rclone.conf
    if mountpoint -q /mnt/lacie; then
      # A read-only mount means a manual job (e.g. a verify pass) owns the
      # drive right now; bail quietly rather than fight over it.
      findmnt -no OPTIONS /mnt/lacie | grep -q '^ro' && {
        echo "/mnt/lacie mounted read-only by someone else; skipping"
        exit 0
      }
    else
      mount -o noatime /dev/disk/by-uuid/${lacieUuid} /mnt/lacie
    fi

    # services/ is deliberately NOT mirrored: it holds live Plex SQLite state
    # (regenerable by a rescan) and the append-only journal archive; the DB
    # that matters (Immich's postgres) rides photos/backups/db via the nightly
    # pg_dump. models/ IS mirrored (renamed from archive/ 2026-08-21) — its
    # weights/ half holds retired, often unreproducible model weights plus
    # Tom's forever collection (docs/nas/model-archive.md). First dump after
    # the rename recopies the tree and parks the old archive/ copy in
    # .previous-versions — expected.
    stamp=$(date +%Y%m%d)
    fail=0
    for tree in photos music documents videos models; do
      src=/mnt/nas/$tree
      [ -d "$src" ] || { echo "$tree: no NAS tree, skipping"; continue; }
      # The LaCie's pre-cutover dirs may differ in case (e.g. Videos).
      dst=$(find /mnt/lacie -maxdepth 1 -type d -iname "$tree" | head -1)
      [ -n "$dst" ] || { dst=/mnt/lacie/$tree; mkdir -p "$dst"; }
      echo "sync $tree: $src -> $dst"
      rclone sync "$src" "$dst" \
        --backup-dir "/mnt/lacie/.previous-versions/$stamp/$tree" \
        --create-empty-src-dirs -v || {
        echo "$tree: sync FAILED"
        fail=1
      }
    done

    # Leftover state from the retired bisync era; harmless, reap if present.
    rm -rf /var/lib/lacie-mirror/photos /var/lib/lacie-mirror/music \
      /var/lib/lacie-mirror/documents /var/lib/lacie-mirror/videos

    umount /mnt/lacie
    echo "lacie-mirror done (fail=$fail) — safe to unplug"
    exit $fail
  '';
in
{
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="${lacieUuid}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="lacie-mirror.service"
  '';

  systemd.services.lacie-mirror = {
    description = "Monthly cold-plug dump: /mnt/nas -> LaCie, one way";
    # A monthly delta over USB can legitimately run for hours.
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mirror;
      TimeoutStartSec = "infinity";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
}
