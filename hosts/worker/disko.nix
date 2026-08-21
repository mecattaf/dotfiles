{
  # Worker install target — the internal WD_BLACK SN7100 500GB NVMe (re-confirmed
  # live 2026-08-21: /dev/nvme0n1, 465.8G, p1 1G ESP + p2 root, exactly this
  # layout). UEFI.
  #
  # ⚠️ DESTRUCTIVE, AND THE BOX IS ALREADY INSTALLED: this declaration exists so
  # the host is reproducible from bare metal, NOT because anything re-runs it.
  # `nixos-rebuild switch` never partitions; only an explicit nixos-anywhere /
  # disko invocation does, and running one against this host would wipe a live
  # fleet member. The 2026-08-21 reintegration deliberately deploys with
  # `nixos-rebuild switch --target-host` for exactly that reason — the host key,
  # and therefore agenix and the mesh registry, must survive.
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
