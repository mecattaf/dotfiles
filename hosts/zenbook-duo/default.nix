{
  inputs,
  lib,
  pkgs,
  ...
}:
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
    # Distributed builds — offload heavy compiles to the worker over the tailnet;
    # the result is cached (attic) so this weak laptop rarely compiles from source.
    # INERT until mySecrets.enable is flipped on below (needs the mesh SSH key).
    ../../modules/build-offload.nix
  ];

  networking.hostName = "zenbook-duo";

  # agenix secret delivery ON — same post-flash two-step the Strix pair went through
  # (the delivered /etc/ssh/ssh_host_ed25519_key matches mesh-registry.nix, so agenix
  # decrypts against it). Delivers the shared tom@mesh SSH key, which is what makes
  # build offloading to the worker (modules/build-offload.nix) live on the laptop.
  mySecrets.enable = true;

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
