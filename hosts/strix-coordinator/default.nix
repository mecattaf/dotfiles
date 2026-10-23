{
  lib,
  ...
}:
# Strix: permanent headless compute host, wired through BE550 to Freebox.
# Private DNS and storage use NAS; public routing is independent of NAS.
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ./uplink-nas.nix

    ./nas-client.nix # temporary media relays and historical /mnt/nas view
    ./services.nix
    ./atuin.nix # retained import; its brain role gate now disables the server
    ../client/audio.nix
    ../../modules/caddy-artifacts.nix
    ../../modules/strix-compute.nix
    ../../modules/browser-desktop.nix
    ../../modules/keyring-autounlock.nix
    ../../modules/handwriting-annotation.nix
  ];

  networking.hostName = "strix-coordinator";
  myFleet.roles = [
    "compute"
  ];
  hardware.bluetooth.enable = lib.mkForce false;

  # Heartbeat remains paused across the NAS handover (DECISIONS 8).
  myGvisor.enable = false;

  # No physical seat (headless in the closet); the Zenbook is the seat.
  # Agent services stay independent of any compositor.
  myDisplay.enable = false;
  services.browser-desktop.enable = true;
  services.handwriting-annotation.enable = true;
  myStrixCompute.immichMl.enable = true;

  # Both stay on their proven pre-migration side until the real HDD and service
  # state have passed the associated issue's cutover checklist.
  # The 2026-08-02 atomic cutover (#131): media core and its PostgreSQL now
  # live on the NAS; the strix keeps only the tailnet identity, the
  # socket relays (2283/4533/32400), the on-demand ML backend, and the NFS
  # client mount at the immutable /mnt/nas path. Both compute hosts now use
  # the NAS PR's shared official Tailscale policy, without advertising routes
  # or exit-node service. The coordinator's enrolled node identity is retained.
  myCoordinatorMedia.enable = false;
  myNasClient.useRemoteStorage = true;
  myNasClient.relayMedia = true;

  services.caddy.virtualHosts."http://drain.internal".extraConfig = ''
    reverse_proxy 127.0.0.1:8740
  '';

  services.utilityModel.enable = true;
  # Compute holds no operator credentials. Existing state is retired separately
  # after NAS session continuity and the sealed backup have been verified.
  mySecrets.enable = false;

}
