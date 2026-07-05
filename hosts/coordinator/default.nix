{ ... }:
# coordinator — AMD Strix Halo (gfx1151), the main device. Router plane
# (router.nix: BE550 gateway/DHCP/DNS + NAS) and rootless quadlets
# (services.nix: adguard/immich/navidrome + sodimo demos, gated on mySecrets).
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ./router.nix
    ./services.nix
    ../../modules/strix.nix
  ];

  networking.hostName = "coordinator";
  myCluster.role = "coordinator";
  myCluster.tbHostId = 1;
}
