{ ... }:
# worker — AMD Strix Halo, headless compute node. No NAS/router/quadlets.
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ./headless-display.nix
    ../../modules/strix.nix
  ];

  networking.hostName = "worker";
  myCluster.role = "worker";
  myCluster.tbHostId = 2;

  # Flipped ON after the 2026-07-05 first boot proved the nixos-anywhere host-key
  # delivery: the same /etc/ssh/ssh_host_ed25519_key that authenticated the box
  # against mesh-registry.nix is agenix's decryption identity.
  mySecrets.enable = true;
}
