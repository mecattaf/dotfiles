{ ... }:
# worker — AMD Strix Halo, the SECONDARY device: headless, specific compute.
# Sunshine/Moonlight (headless niri via faked EDID connector) lands via ./sunshine.nix
# (task #7; see ~/mecattaf/sunshine-moonlight-research.md). No NAS/router/quadlets.
{
  imports = [
    ./hardware.nix
    ../../modules/strix.nix
    # ./sunshine.nix   # ROLLED BACK 2026-06-20 — kept as a deferred STUB (see the file).
    #                    Uncomment to activate sunshine/moonlight later. "I'll use that later."
  ];

  networking.hostName = "worker";
  myCluster.role = "worker";
  myCluster.tbHostId = 2;
}
