{
  # Worker install target — the internal WD_BLACK SN7100 500GB NVMe (verified over
  # TB3 pre-flight 2026-07-05). UEFI. nixos-anywhere runs this to partition + format.
  # ⚠️ DESTRUCTIVE: wipes /dev/nvme0n1 on install (worker full-reset is intended).
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
