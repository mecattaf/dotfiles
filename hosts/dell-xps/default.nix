{ inputs, pkgs, ... }:
# dell-xps — Intel XPS 13 9315 (dev laptop). Power owned by power-profiles-daemon (NO TLP).
{
  imports = [
    ./hardware.nix
    inputs.nixos-hardware.nixosModules.dell-xps-13-9315
  ];

  networking.hostName = "dell-xps";

  # Intel Arc/Xe VA-API — deliberately iHD (not legacy i965).
  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
}
