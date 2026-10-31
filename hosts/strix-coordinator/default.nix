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

    ./nas-client.nix # /mnt/nas NFS view and the NAS reachability tripwire
    ./atuin.nix # retained import; its brain role gate now disables the server
    ../client/audio.nix
    ../../modules/strix-compute.nix
    ../../modules/browser-desktop.nix
    ../../modules/keyring-autounlock.nix
  ];

  networking.hostName = "strix-coordinator";
  myFleet.roles = [
    "compute"
  ];
  hardware.bluetooth.enable = lib.mkForce false;

  # No physical seat (headless in the closet); the Zenbook is the seat.
  # Agent services stay independent of any compositor.
  myDisplay.enable = false;
  services.browser-desktop.enable = true;
  myStrixCompute.immichMl.enable = true;

  # The NAS hosts Immich, Navidrome and every .internal front door (Caddy,
  # hosts/nas/front-door.nix). This host keeps its own enrolled Tailscale
  # identity as the independent recovery box (modules/fleet-transport.nix) and
  # the NFS client mount at the immutable /mnt/nas path.
  myNasClient.useRemoteStorage = true;

  services.utilityModel.enable = true;
  # The TP2 rank shape stays, but each rank needs the full 340.6 GiB Q2 and
  # this disk has 108 GB free (D-A), so ds4's files are not wanted here: a
  # default borrow does not try them and prune would remove a stray copy.
  services.ds4.wanted = false;
  # Compute holds no operator credentials. Existing state is retired separately
  # after NAS session continuity and the sealed backup have been verified.
  mySecrets.enable = false;

}
