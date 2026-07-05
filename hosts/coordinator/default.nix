{ ... }:
# coordinator — AMD Strix Halo (gfx1151), the main device. Router plane, NAS CIFS
# mount, and quadlets (adguard/immich/navidrome) land here incrementally.
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../modules/strix.nix
  ];

  networking.hostName = "coordinator";
  myCluster.role = "coordinator";
  myCluster.tbHostId = 1;
}
