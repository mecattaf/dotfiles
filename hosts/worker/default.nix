{ ... }:
# worker — AMD Strix Halo, the SECONDARY device: headless, specific compute.
# Sunshine/Moonlight (headless niri via faked EDID connector) lands via ./sunshine.nix
# (task #7; see ~/mecattaf/sunshine-moonlight-research.md). No NAS/router/quadlets.
{
  imports = [
    ./hardware.nix
    ../../modules/strix.nix
    # ./sunshine.nix   # added in task #7
  ];

  networking.hostName = "worker";
  myCluster.role = "worker";
  myCluster.tbHostId = 2;
}
