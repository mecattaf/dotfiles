{ ... }:
# coordinator — AMD Strix Halo (gfx1151), the main device. Freebox wifi uplink +
# directly-attached NAS (uplink-nas.nix) and the native media services
# (services.nix: services.immich + services.navidrome, on /mnt/nas). DNS
# ad/tracker filtering comes from the NAS LAN resolver (10.42.0.1) since the
# 2026-08-21 cutover — see the removal note in the imports list below.
# The old rootless podman quadlet stack — AdGuard, Immich, Navidrome —
# was retired 2026-07-13 (AdGuard with the BE550 router; Immich/Navidrome moved
# to native modules), leaving this host container-free.
{
  imports = [
    ./hardware.nix
    ./disko.nix
    # ./fleet-deploy.nix DELETED 2026-08-21 (Tom: "fleet-deploy is DEAD…the
    # nas-centricity supersedes that fully"). The nightly coordinator-builds-
    # and-pushes transaction — including its push-activation of the NAS and
    # its own ⚠ failure-marker fish hook — is replaced by the update-center
    # model: the NAS builds nightly and publishes to attic; every device,
    # including this one, pulls and activates on its own schedule. Manual
    # deploys still work via the flake's deploy-rs nodes (`deploy .#nas`).
    ./uplink-nas.nix
    ./journal-upload.nix # fleet journald substrate sender — refs #135
    ./nas-client.nix
    ./backups.nix # #130 ws2b: nightly borg push to the NAS append-only repo
    ./services.nix
    ./immich-ml.nix
    ./atuin.nix
    ./audio.nix # pins the webcam mic as the default PipeWire source
    # AdGuard REMOVED from this host at cutover phase 3 (2026-08-21, Tom's
    # ruling: "adguard shall now run only on the NAS"). Not just redundant —
    # actively incompatible with the repeated LAN: the loopback instance's
    # upstreams are DoH to 1.1.1.1/1.0.0.1/9.9.9.9, exactly the IPs the NAS's
    # dns_hijack drops on tcp/443 (hosts/nas/router.nix), so DNS would go dark
    # the moment this box joined `thomas`. Filtering now comes from the LAN
    # resolver (10.42.0.1) via DHCP; on the freebox-uplink fallback rail DNS is
    # the Freebox's, unfiltered — accepted. The Zenbook Duo still imports the
    # module and must shed it (or be exempted from the DoH drop list) before it
    # ever gets a be550 profile.
    ./attic.nix # fleet binary-cache server (atticd over the tailscale mesh) — refs #42
    # Artifact serving plane: Caddy drop-dir + TTL reaper (publish-artifact
    # skill's tailnet rung). Live origins stay local on 127.0.0.1.
    ../../modules/caddy-artifacts.nix
    # Durable microVM host. Guest ports used as live-artifact origins are
    # forwarded to coordinator loopback and consumed locally by Caddy.
    ../../modules/microvm-host.nix
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
  # Flipped post-flash after the zero-TOFU host-key check (2026-07-05): the
  # delivered /etc/ssh/ssh_host_ed25519_key matched mesh-registry.nix, so
  # agenix may now decrypt against it.
  mySecrets.enable = true;

}
