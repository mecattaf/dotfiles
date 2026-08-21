{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./unstable-pkgs.nix
    ./hardware.nix
    ./disko.nix
    ./network.nix
    ./router.nix # 2026-08-20: NAS is the house router (A8500 uplink + BE550 LAN)
    ./journal.nix
    ./storage.nix
    ./discovery.nix # Avahi + read-only SMB so the NAS shows up in Nautilus (2026-08-21)
    ./media.nix
    # ./phone-ingest.nix DELETED 2026-08-21 (Tom: "DEAD and no longer needed
    # ever again") — the adb camera-roll pull was superseded by the Immich
    # mobile app's own background backup. See git history for the tooling.
    ./lacie-mirror.nix
    # #130 expansion workstreams. All four land with their gates OFF; each has
    # a runbook in its own header and flips on its own, later, after that
    # runbook has been walked on the real hardware. ./wake-helpers.nix is
    # deliberately absent — it is a plain function file, not a module.
    ./snapshots.nix # ws2a btrbk snapshots of the data subvolumes
    ./backups.nix # ws2b append-only borg repo server
    ./models.nix # the model Library: weights forever-collection + static cache (was ws4 archive.nix)
    ./attic.nix # ws5  fleet binary cache, relayed by the coordinator
    ./paperless.nix # #136 Paperless v3 same-inode PDF projection, gate OFF
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
  # The model Library (was ws4 archive, renamed 2026-08-21 — migration runbook
  # in models.nix): weights/ holds the forever collection (first residents:
  # the rescued FastFlowLM trees, moved from archive/models/flm), cache/ is
  # the nightly static binary cache. compression=none subvolume, created live
  # 2026-08-20. docs/nas/model-archive.md is the retire/restore runbook, and
  # retired catalog rows must carry an `archived` receipt (asserted in
  # modules/local-models.nix).
  myNas.models.enable = true;
  # ws2a snapshots — flipped 2026-08-21 per the runbook in ./snapshots.nix:
  # subvolume layout verified live (photos/music/documents/videos/services/
  # .snapshots all real subvolumes), dry-run + coordinator containment check
  # done at deploy time. Cadence: MONTHLY, first Saturday 08:00 (see the COST
  # paragraph in snapshots.nix for the ruling trail).
  myNas.snapshots.enable = true;

  # amdtop — the same telemetry TUI the coordinator runs (modules/strix-ai.nix).
  # This box is AMD on both halves: common-cpu-amd/kvm-amd, plus the radeonsi
  # iGPU already driving Immich's VA-API transcodes above, so the GPU pane is
  # live here rather than empty. The XDNA pane stays empty — no NPU on this
  # board — which amdtop handles by omission.
  #
  # Sourced from nix-strix-halo because amdtop is in NEITHER nixpkgs pin, stable
  # or unstable, so unstablePkgs is not an option. That input is a rolling one
  # (rollingInputOverrides), which means this single leaf TUI moves nightly while
  # the appliance's stable base does not. Accepted deliberately: nothing on the
  # host depends on it, it is operator tooling reached over SSH. It also brings
  # its own ~62 MB glibc/libdrm chain, shared with nothing else in this closure.
  environment.systemPackages = [
    inputs.nix-strix-halo.packages.${pkgs.stdenv.hostPlatform.system}.amdtop
  ];

  system.stateVersion = "26.05";
}
