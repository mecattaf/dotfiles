{
  inputs,
  lib,
  ...
}:
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ./network.nix
    ./storage.nix
    ./media.nix
    ../../modules/adguardhome.nix
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-pc
  ];

  networking.hostName = "nas";
  myHeadless.enable = true;

  # No shared agenix payload or overlay network is needed on this appliance.
  # The coordinator is its only peer and tailnet-facing relay; deploy-rs reaches
  # SSH directly on 10.77.0.2.
  mySecrets.enable = false;
  services.tailscale.enable = lib.mkForce false;
  services.tailscale.extraUpFlags = lib.mkForce [ ];
  services.tailscale.extraSetFlags = lib.mkForce [ ];

  # Preserve graphics/VA-API for headless Immich video transcoding. This does
  # not install or start a display server, compositor, or graphical login.
  hardware.graphics.enable = true;
  environment.sessionVariables.LIBVA_DRIVER_NAME = "radeonsi";

  # The appliance is safe to flash onto eMMC before the data disk arrives.
  # Both gates stay false until the plug-in runbook records real device IDs,
  # migrates state, and validates the result.
  myNas.storage.enable = false;
  myNas.media.enable = false;

  system.stateVersion = "26.05";
}
