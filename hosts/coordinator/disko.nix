{
  # Coordinator install target — the internal WD_BLACK SN7100 1TB NVMe, VERIFIED on
  # the live machine 2026-07-05 (`lsblk`: nvme0n1, 931.5G). Flashed LAST during
  # the initial fleet bring-up. Standard layout: 1G ESP + ext4 root over the
  # old placeholder's xfs.
  # ⚠️ DESTRUCTIVE: wipes /dev/nvme0n1. Run the TASK-39 secrets/state export first.
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
