{ ... }:
# coordinator — AMD Strix Halo (gfx1151), the main device. Router plane
# (router.nix: BE550 gateway/DHCP/DNS + NAS) and rootless quadlets
# (services.nix: adguard/immich/navidrome + sodimo demos, gated on mySecrets).
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ./router.nix
    ./services.nix
    ../../modules/strix.nix
  ];

  networking.hostName = "coordinator";
  myCluster.role = "coordinator";
  myCluster.tbHostId = 1;

  # Flipped post-flash after the zero-TOFU host-key check (2026-07-05): the
  # delivered /etc/ssh/ssh_host_ed25519_key matched mesh-registry.nix, so
  # agenix may now decrypt against it (same two-step as the worker).
  mySecrets.enable = true;
}
