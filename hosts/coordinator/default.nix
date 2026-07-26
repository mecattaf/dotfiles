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
    ./services.nix
    # Per-machine AdGuard Home DNS filter (loopback 127.0.0.1:53, resolved
    # forwards to it). Proven on the worker first (2026-07-13) before landing on
    # this main device. Same import on worker + zenbook-duo.
    ../../modules/adguardhome.nix
    ./attic.nix # fleet binary-cache server (atticd over the tailscale mesh) — refs #42
    # Artifact serving plane: Caddy drop-dir + TTL reaper (publish-artifact
    # skill's tailnet rung). Coordinator = fleet front door; origins on worker.
    ../../modules/caddy-artifacts.nix
    ../../modules/strix.nix
    # Desktop-only local-media plane: mDNS discovery (avahi) + AirPlay output for
    # the JBL Authentics 200 + CUPS/driverless printing for the Brother. refs the
    # 2026-07-24 "Chrome can't find the JBL" fix (mDNS was firewalled off).
    ../../modules/desktop-media.nix
  ];

  networking.hostName = "coordinator";
  myCluster.role = "coordinator";

  # Flipped post-flash after the zero-TOFU host-key check (2026-07-05): the
  # delivered /etc/ssh/ssh_host_ed25519_key matched mesh-registry.nix, so
  # agenix may now decrypt against it (same two-step as the worker).
  mySecrets.enable = true;

}
