{ lib, ... }:
{
  # UNVERIFIED PLACEHOLDER: the DXP2800 GT is specified with internal eMMC, but
  # its Linux device name must be confirmed with lsblk before nixos-anywhere is
  # allowed to run. The associated issue treats that confirmation as a hard,
  # destructive-action gate.
  disko.devices.disk.system = {
    type = "disk";
    device = lib.mkDefault "/dev/mmcblk0";
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

  # UNVERIFIED PLACEHOLDER, same discipline as the eMMC above: confirm the live
  # device name before nixos-anywhere runs. 256GB NVMe (Fanxiang S500 Pro,
  # issue #135): the journald-remote home. Journal writeback belongs on this
  # SSD — it would be wear on the eMMC and spin-up poison for the future HDD.
  # Formatting it in the same disko run means the first flash is the only flash.
  disko.devices.disk.journal = {
    type = "disk";
    device = lib.mkDefault "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions.journal = {
        size = "100%";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/var/log/journal/remote";
          mountOptions = [
            "noatime"
            "nofail"
          ];
        };
      };
    };
  };
}
