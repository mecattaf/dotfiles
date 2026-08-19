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
    ./journal.nix
    ./storage.nix
    ./media.nix
    ./phone-ingest.nix
    ./lacie-mirror.nix
    # #130 expansion workstreams. All four land with their gates OFF; each has
    # a runbook in its own header and flips on its own, later, after that
    # runbook has been walked on the real hardware. ./wake-helpers.nix is
    # deliberately absent — it is a plain function file, not a module.
    ./snapshots.nix # ws2a btrbk snapshots of the data subvolumes
    ./backups.nix # ws2b append-only borg repo server
    ./archive.nix # ws4  cold archive subvolume for retired model weights
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
  # Operator tooling only — adb, the Immich CLI, and a staging directory (#143).
  # Nothing here starts on its own; the first camera-roll pull is driven by hand
  # so its failure modes get observed before any of it is automated.
  myNas.phoneIngest.enable = true;

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
