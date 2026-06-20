{ ... }:
# coordinator — AMD Strix Halo (gfx1151), the MAIN device: NAS / LAN-router / quadlets.
# Router plane, NAS CIFS mount, quadlets (adguard/immich/navidrome), and the Thunderbolt
# cluster fabric land here incrementally (see harness-sweep.md). Headless-access saga
# collapses under declarative authorized_keys + TB static IPs.
{
  imports = [
    ./hardware.nix
    ../../modules/strix.nix
  ];

  networking.hostName = "coordinator";
  myCluster.role = "coordinator";
  myCluster.tbHostId = 1;
}
