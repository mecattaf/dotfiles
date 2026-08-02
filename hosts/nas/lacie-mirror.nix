{ lib, pkgs, ... }:
# Quarterly cold-storage mirror (Tom's ruling 2026-08-02): the LaCie 4TB lives
# unplugged in a drawer; roughly once a quarter it gets plugged into a NAS USB
# port and everything that changed on either side syncs — both ways, plain
# rclone bisync, no monitoring, no ceremony. Plug in, wait for the unit to
# finish, unplug. That plug event IS the trigger: udev matches the LaCie's
# Btrfs UUID (pinned since the 2026-07-23 NTFS→Btrfs migration) and starts the
# service. The mount point is /mnt/lacie — never /mnt/nas (#131).
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
    # Local-path bisync needs no real config, but without HOME rclone hunts
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

    # services/ is deliberately NOT mirrored: it holds live PostgreSQL data
    # and a file-level copy of a running database is torn on the way out and
    # destructive on the way back. Media trees only.
    fail=0
    for tree in photos music documents videos; do
      src=/mnt/nas/$tree
      [ -d "$src" ] || { echo "$tree: no NAS tree, skipping"; continue; }
      # The LaCie's pre-cutover dirs may differ in case (e.g. Videos).
      dst=$(find /mnt/lacie -maxdepth 1 -type d -iname "$tree" | head -1)
      [ -n "$dst" ] || { dst=/mnt/lacie/$tree; mkdir -p "$dst"; }
      wd=/var/lib/lacie-mirror/$tree
      mkdir -p "$wd"
      # First run per tree establishes the bisync baseline automatically.
      resync=""
      [ -n "$(ls -A "$wd")" ] || resync="--resync"
      echo "bisync $tree: $src <-> $dst $resync"
      rclone bisync "$src" "$dst" --workdir "$wd" \
        --resilient --recover --create-empty-src-dirs -v $resync || {
        echo "$tree: bisync FAILED"
        fail=1
      }
    done

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
    description = "Quarterly cold-plug mirror: /mnt/nas <-> LaCie, both ways";
    # A quarterly delta over USB can legitimately run for hours.
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mirror;
      TimeoutStartSec = "infinity";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
}
