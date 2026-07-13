{ ... }:
# worker — AMD Strix Halo, headless compute node. No NAS/router/quadlets.
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ./headless-display.nix
    ./cache-push.nix
    ./fleet-prebuild.nix # 02:00 cache warmer for fleet auto-update (builds all hosts → attic)
    ./gpu-cooldown.nix
    ../../modules/strix.nix
    ../../modules/microvm-host.nix
    # Per-machine AdGuard Home DNS filter (loopback 127.0.0.1:53, resolved
    # forwards to it). Proving ground for the fleet-wide rollout — enabled here
    # FIRST because the worker is headless, so a DNS misstep can't lock Tom out
    # of Claude Code. Coordinator + zenbook get the same import once proven.
    ../../modules/adguardhome.nix
  ];

  networking.hostName = "worker";
  myCluster.role = "worker";
  myCluster.tbHostId = 2;

  # GPU thermal cooldown tripwire — poll junction/Tctl, and on a sustained trip
  # enqueue a 30-min worker-gpu cooldown lease through tally on the coordinator.
  services.gpuCooldownTripwire.enable = true;

  # Flipped ON after the 2026-07-05 first boot proved the nixos-anywhere host-key
  # delivery: the same /etc/ssh/ssh_host_ed25519_key that authenticated the box
  # against mesh-registry.nix is agenix's decryption identity.
  mySecrets.enable = true;
}
