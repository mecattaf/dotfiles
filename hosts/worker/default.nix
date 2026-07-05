{ ... }:
# worker — AMD Strix Halo, headless compute node. No NAS/router/quadlets.
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ./headless-display.nix
    ../../modules/strix.nix
  ];

  networking.hostName = "worker";
  myCluster.role = "worker";
  myCluster.tbHostId = 2;
}
