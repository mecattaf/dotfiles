{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./agent-host.nix
    ./unstable-pkgs.nix
    ./kernel.nix # retain the validated kernel series during the network move
    ./hardware.nix
    ./disko.nix
    ./tailscale.nix
    ./network.nix
    ./initrd-ssh.nix # stage-1 SSH on 10.42.0.1:2222 for headless boot failures
    ./router.nix # Gateway, DHCP and DNS; Ethernet upstream through BE550
    # printer-keepalive.nix DELETED same-day it was born (Tom: "there has to
    # be a smarter way"): with the CUPS queue dialing the printer's pinned IP
    # (modules/printing.nix), a print job itself wakes the Brother from Deep
    # Sleep — the timer was belt-and-suspenders for a failure mode the IP
    # queue already killed. VERIFIED 2026-08-21: after ~4h idle in Deep
    # Sleep, CUPS job 88 (model census) woke the printer via the pinned-IP
    # queue and printed — no keepalive anywhere.
    ./nix-builds.nix # 2026-08-22: build scratch off the eMMC + in-build auto-GC
    ./nix-on-nvme.nix # 2026-08-22: /nix onto the M.2 — GATE OFF, reboot-only (#232)
    ./journal.nix
    ./storage.nix
    ./home-disk.nix # #599, bench-prepared home; stage before the fleet power-off
    ./memory-disk.nix # 256GB recording/memory reservation, gated until fast-tier move
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
    # backups.nix (ws2b borg) DELETED 2026-08-21 unbuilt — Tom's ruling:
    # "real backups are physical redundancy, not a backup sitting on the
    # same device." The protection stack is snapshots + RAID 1 + LaCie.
    ./models.nix # the model Library: weights forever-collection + static cache
    ./attic.nix # ws5  fleet binary cache, served directly (executed 2026-08-21)
    ./update-center.nix # nightly fleet builds -> attic (the App Store model)
    ../../modules/adguardhome.nix
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-pc
  ];

  networking.hostName = "nas";
  myFleet.roles = [
    "router"
    "brain"
  ];
  myHeadless.enable = true;

  # Central credentials move here with the brain role. Ciphertexts must be
  # rekeyed by Tom before deployment; see REKEY.md. No compute host receives them.
  mySecrets.enable = true;

  # ── THE TAILNET, AND WHOSE CONTROL PLANE IT IS ─────────────────────────
  #
  # TAILSCALE ON — Tom's ruling 2026-08-21: "everything at home goes through
  # the NAS! so let's have the NAS be the tailscale sink." That reversed the
  # 2026-08-04-era mkForce-disables (which belonged to the world where the
  # strix was the only door to the internet), and it still holds: this
  # box is the tailnet node, and it is a SUBNET ROUTER advertising the whole
  # LAN so a roaming laptop reaches every home device — NAS services,
  # printer, strix — through one node.
  #
  # The NAS is the sole official Tailscale subnet router (2026-10-08).

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
  # disk; deployment order (NAS restore first, then the strix cutover)
  # is sequenced manually in #131.
  myNas.media.enable = true;
  myNas.models.enable = true;
  # ws2a snapshots — flipped on 2026-08-21, OFF since 2026-10-28 on Tom's word:
  # "dleete the nine snapshots and turn off job YES. no time machine for file
  # etc". The snapshots and the .snapshots subvolume were deleted by hand the
  # same day; the 4TB holds music, photos, videos, Documents and the model
  # Library only.
  myNas.snapshots.enable = false;
  # ws5 — flipped 2026-08-21 per the runbook in ./attic.nix: state rsynced
  # from the strix with atticd stopped, signing key verified intact,
  # env file placed on the root NVMe.
  myNas.attic.enable = true;
  # The App Store's build half — nightly 01:30, capped to the bottom of every
  # scheduler, publishes to the local attic. Devices pull; nothing is pushed.
  #
  # Back ON 2026-08-22 in the same commit that flips myNas.nixOnNvme below —
  # the pairing is the point. It was briefly turned off that morning when the
  # 57G eMMC could not hold three closures; disabling the build farm made the
  # symptom stop without fixing the siting, which was the wrong answer. The
  # store now lives on the 256G M.2, so the farm has room to do its job.
  myNas.updateCenter.enable = true;
  # Nightly build parked (Tom, 2026-09-28): it peaked at 15.5G + 1.4G swap on
  # this 24G router, and builds belong on the desktops, run by hand. The
  # service stays hand-startable and the candidates keep being served, so
  # update-adopt on the devices sees the last good closure, not an error.

  # ── /nix on the M.2 (#232) ──────────────────────────────────────────────
  # Flipped after the runbook in ./nix-on-nvme.nix was walked on the real
  # hardware: store rsync'd with -aHAX, verified, `nixos-rebuild boot`, and a
  # SUPERVISED reboot with a console on the HDMI corner. Never flip this
  # remotely — /nix is a neededForBoot mount and a mistake does not degrade,
  # it means the house router does not come up.
  myNas.nixOnNvme.enable = true;
  myNas.homeDisk.enable = true;

  # amdtop — the same telemetry TUI the strix runs (modules/strix-ai.nix).
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

    # `hf` on the appliance (2026-08-28). library-fetch is the automated path and
    # needs no CLI, but the Library is where models actually land, so stocking one
    # by hand should not mean shelling to another box. The wrapper reads
    # /run/agenix/huggingface-token, which this host now receives — so it is
    # authenticated here for the same reason and by the same mechanism as the
    # nightly, with no login flow and nothing written into $HF_HOME.
    pkgs.huggingface-cli
  ];

  system.stateVersion = "26.05";
}
