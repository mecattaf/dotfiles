{ ... }:
{
  # VERIFIED LIVE 2026-08-01 (issue #131 destructive-action gate): 58.3GiB
  # internal eMMC, confirmed by lsblk/by-id on the running vendor OS with the
  # HDD bays empty. Wipe signed off by Tom ("wipe both") before the first
  # nixos-anywhere run.
  disko.devices.disk.system = {
    type = "disk";
    device = "/dev/disk/by-id/mmc-CG1051_0xd755b207";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };

  # VERIFIED LIVE 2026-08-01, same sign-off as the eMMC above: factory-blank
  # 238.5GiB NVMe. Formatted in the same disko run so the first flash is the
  # only flash.
  #
  # Role widened 2026-08-02 (Tom): originally the journald-remote home alone
  # (#135), which used ~50MB of 233G. Now the general fast tier at /mnt/fast —
  # remote journal (bind, journal.nix), PostgreSQL, Navidrome state, Immich
  # generated media (media.nix). Random-I/O state belongs here: it would be
  # wear on the eMMC and seek chatter on the HDD. The mountpoint move was
  # non-destructive — same filesystem, never reformatted.
  disko.devices.disk.journal = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-Fanxiang_S500Pro_256GB_26040259615000015";
    content = {
      type = "gpt";
      partitions.journal = {
        size = "100%";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/mnt/fast";
          mountOptions = [
            "noatime"
            "nofail"
          ];
        };
      };
    };
  };
}
