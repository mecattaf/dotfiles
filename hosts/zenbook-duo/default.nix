{ inputs, pkgs, ... }:
# zenbook-duo — Intel Asus Zenbook Duo UX8406 (dual-screen). The FIRST flash target.
# No dedicated nixos-hardware module → compose generics. Second display + IPU6 webcam +
# the zenbook-duo-daemon / titdb touchpad bits are follow-ups (niri / out-of-nixpkgs).
{
  imports = [
    ./hardware.nix
    inputs.nixos-hardware.nixosModules.common-cpu-intel
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
  ];

  networking.hostName = "zenbook-duo";

  boot.kernelParams = [ "i915.enable_psr=0" ]; # eDP PSR flicker

  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  services.asusd.enable = true; # kbd backlight, charge-limit, platform-profile
}
