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
    ./journal.nix
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

  # Device identity recorded by the Day-2 runbook (#131) from the live disk:
  # WD Red Plus 4TB, SMART-verified 2026-08-02, short self-test clean.
  myNas.storage = {
    enable = true;
    filesystemUuid = "2345893a-8769-492c-90cb-23b79984a559";
    smartDevice = "/dev/disk/by-id/ata-WDC_WD40EFZZ-68CPAN0_WD-WXB2D166SAR7";
  };
  # Flipped by the Day-2 runbook once the LaCie data landed on the verified
  # disk; deployment order (NAS restore first, then the coordinator cutover)
  # is sequenced manually in #131.
  myNas.media.enable = true;

  system.stateVersion = "26.05";
}
