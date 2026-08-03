{ ... }:
# coordinator — AMD Strix Halo (gfx1151), the main device. Freebox wifi uplink +
# directly-attached NAS (uplink-nas.nix) and the native media services
# (services.nix: services.immich + services.navidrome, on /mnt/nas). DNS
# ad/tracker filtering is per-box (../../modules/adguardhome.nix, a loopback
# resolver). The old rootless podman quadlet stack — AdGuard, Immich, Navidrome —
# was retired 2026-07-13 (AdGuard with the BE550 router; Immich/Navidrome moved
# to native modules), leaving this host container-free.
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ./fleet-deploy.nix # one Tally-owned deploy-rs transaction for the whole fleet
    ./uplink-nas.nix
    ./journal-upload.nix # fleet journald substrate sender — refs #135
    ./nas-client.nix
    ./backups.nix # #130 ws2b: nightly borg push to the NAS append-only repo
    ./services.nix
    ./immich-ml.nix
    ./atuin.nix
    # Per-machine AdGuard Home DNS filter (loopback 127.0.0.1:53, resolved
    # forwards to it). The Zenbook Duo imports the same module.
    ../../modules/adguardhome.nix
    ./attic.nix # fleet binary-cache server (atticd over the tailscale mesh) — refs #42
    # Artifact serving plane: Caddy drop-dir + TTL reaper (publish-artifact
    # skill's tailnet rung). Live origins stay local on 127.0.0.1.
    ../../modules/caddy-artifacts.nix
    # Durable microVM host. Guest ports used as live-artifact origins are
    # forwarded to coordinator loopback and consumed locally by Caddy.
    ../../modules/microvm-host.nix
    # Local GPU temperature tripwire; its Tally hold targets coordinator-gpu.
    ../../modules/gpu-cooldown.nix
    ../../modules/cli-anything.nix
    ../../modules/strix.nix
  ];

  networking.hostName = "coordinator";
  # Both stay on their proven pre-migration side until the real HDD and service
  # state have passed the associated issue's cutover checklist.
  # The 2026-08-02 atomic cutover (#131): media core and its PostgreSQL now
  # live on the NAS; the coordinator keeps only the tailnet identity, the
  # socket relays (2283/4533/32400), the on-demand ML backend, and the NFS
  # client mount at the immutable /mnt/nas path.
  myCoordinatorMedia.enable = false;
  myNasClient.useRemoteStorage = true;
  myNasClient.relayMedia = true;
  services.gpuCooldownTripwire = {
    enable = true;
    # Retuned 2026-07-29 after the academic-ocr supervised run: sustained VLM
    # inference sits near the old 85C Tctl default, so the tripwire fired
    # mid-run and then held coordinator-gpu for 30 minutes while the die sat
    # at 52C. Strix Halo firmware self-throttles near 100C; the tripwire is a
    # backstop, not the primary governor. Trip later, hold briefly: the die
    # returns to ambient-idle temperature within a couple of minutes.
    tctlThresholdC = 93;
    junctionThresholdC = 95;
    sustainSeconds = 120;
    cooldownMinutes = 8;
  };

  # Flipped post-flash after the zero-TOFU host-key check (2026-07-05): the
  # delivered /etc/ssh/ssh_host_ed25519_key matched mesh-registry.nix, so
  # agenix may now decrypt against it.
  mySecrets.enable = true;

}
