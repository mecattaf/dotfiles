{
  # Install only the returning 1TB; these PARTUUIDs are freshly generated.
  disko.devices.disk.w1t = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-WD_BLACK_SN7100_1TB_26051Y809195";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          uuid = "6ff12253-34de-4c8b-9b1f-80aa259d0c4e";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          uuid = "d7642423-57b2-47b7-acc6-fe553fd55972";
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
