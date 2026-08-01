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
}
