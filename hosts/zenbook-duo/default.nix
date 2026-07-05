{ inputs, lib, pkgs, ... }:
# zenbook-duo — Intel Asus Zenbook Duo UX8406 (dual-screen). The FIRST flash target.
# No dedicated nixos-hardware module → compose generics. Second display + IPU6 webcam +
# the zenbook-duo-daemon / titdb touchpad bits are follow-ups (niri / out-of-nixpkgs).
{
  imports = [
    ./hardware.nix
    ./disko.nix
    inputs.nixos-hardware.nixosModules.common-cpu-intel
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
  ];

  networking.hostName = "zenbook-duo";

  boot.kernelParams = [ "i915.enable_psr=0" ]; # eDP PSR flicker

  # jul5 dual-eDP niri startup hang mitigation (NEEDS LIVE VERIFY): niri.service is
  # Type=notify and was SIGKILLed at systemd's 90s default before signalling ready.
  # Give it rope so a *slow* (vs deadlocked) start survives and can be diagnosed from
  # the journal. This is a diagnostic aid, not a proven fix — pair with the early i915
  # KMS in hardware.nix and check `journalctl --user -u niri -b` on next boot.
  systemd.user.services.niri.serviceConfig.TimeoutStartSec = lib.mkForce "120";

  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  services.asusd.enable = true; # kbd backlight, charge-limit, platform-profile
  services.thermald.enable = true; # Intel thermal throttling protection (decided: Intel-only)
}
