{
  # XPS 13 9315 install target. Same layout as the worker (1G ESP + ext4 root).
  # ⚠️ DESTRUCTIVE: wipes the disk below. Device name is the near-universal laptop
  # default but UNVERIFIED on this machine — confirm with `lsblk` from the booted
  # installer BEFORE flashing and fix here if it differs.
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
