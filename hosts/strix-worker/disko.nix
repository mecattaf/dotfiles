{
  # The returning disk is occupied. Preserve its measured 2026-10-23 GPT IDs
  # so a supervised, non-repartitioning install can retain the ext4 root/home.
  # This is a layout declaration, NOT permission to run disko or format it.
  # See docs/strix-worker-install.md; the ESP has no detected filesystem yet.
  disko.devices.disk.w1t = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-WD_BLACK_SN7100_1TB_26051Y809195";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          uuid = "25db1b50-f51c-499b-a628-26a25fa02662";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          uuid = "e4869fbf-f6c5-4bf5-960f-cf19376e139d";
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
