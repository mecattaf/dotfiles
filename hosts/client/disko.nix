# /dev/nvme0n1 = Sandisk SN560/SN740 953.9G. 1G ESP + ext4 root, unencrypted,
# no swap partition (zram carries it, which is also why hibernate is off).
#
# This is the layout omarchy-fleet's lib/laptop-disko.nix put on the disk on
# 2026-09-07 and that `lsblk` showed live on 2026-09-11 (disk-main-ESP vfat
# /boot, disk-main-root ext4 /), so the 2026-09-11 return was an in-place
# `nixos-rebuild switch --target-host` and this file only generated the
# fileSystems entries. It matters again only at a future reflash.
#
# ⚠️ DESTRUCTIVE under nixos-anywhere: confirm `lsblk -dno NAME,SIZE,MODEL`
# from the installer before ever running it.
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/nvme0n1";
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
}
