{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./unstable-pkgs.nix
    ./kernel.nix # 2026-08-29: linux 7.2 for the mt7925u uplink dongle (#244 NAS scope)
    ./hardware.nix
    ./disko.nix
    ./network.nix
    ./router.nix # 2026-08-20: NAS is the house router (A8500 uplink + BE550 LAN)
    ./wan-watchdog.nix # 2026-08-28: software recovery for the mt7925u wedge (#235 post-mortem)
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
    ./models.nix # the model Library: weights forever-collection + static cache (was ws4 archive.nix)
    ./attic.nix # ws5  fleet binary cache, served directly (executed 2026-08-21)
    ./update-center.nix # nightly fleet builds -> attic (the App Store model)
    ./paperless.nix # #136 Paperless v3 same-inode PDF projection, gate OFF
    ./tv.nix # niri TV session on the HDMI corner + wayvnc (2026-08-21)
    ./headscale.nix # 2026-09-01: the fleet's OWN tailnet control plane (supersedes #233)
    ../../modules/adguardhome.nix
    inputs.nixos-hardware.nixosModules.common-cpu-amd
    inputs.nixos-hardware.nixosModules.common-pc
  ];

  networking.hostName = "nas";
  myHeadless.enable = true;

  # agenix ON since 2026-08-28 — and the doctrine still holds, because the
  # doctrine was never "no agenix here", it was "no STANDING decryption
  # authority over ciphertext this box never reads" (the aug04 ruling that
  # pulled the appliance out of the whole common tier). That text names its own
  # exception: flip this on and "add its key back [to secrets.nix] for the
  # specific secrets it consumes, not wholesale."
  #
  # Consumed: huggingface-token, and nothing else. The nas is a recipient of
  # exactly one ciphertext (secrets.nix `nasOnly`) and can decrypt no other —
  # not tom's password hash, not the fleet SSH key, not atuin's. Those blocks
  # are explicitly gated away from this host; see the invariant note in
  # modules/secrets.nix before adding the next secret.
  #
  # Why it was needed: ./models.nix's library-fetch downloads catalog weights
  # from Hugging Face anonymously, so gated repos 401 the nightly.
  # (The attic RS256 secret remains a runbook-placed file, see ./attic.nix.)
  mySecrets.enable = true;

  # ── THE TAILNET, AND WHOSE CONTROL PLANE IT IS ─────────────────────────
  #
  # TAILSCALE ON — Tom's ruling 2026-08-21: "everything at home goes through
  # the NAS! so let's have the NAS be the tailscale sink." That reversed the
  # 2026-08-04-era mkForce-disables (which belonged to the world where the
  # coordinator was the only door to the internet), and it still holds: this
  # box is the tailnet node, and it is a SUBNET ROUTER advertising the whole
  # LAN so a roaming laptop reaches every home device — NAS services,
  # printer, coordinator — through one node.
  #
  # What changed 2026-09-01, on Tom's ruling that "self-hosted headscale
  # lands on the NAS and becomes the control plane for everything": the
  # tailnet this box is a node OF is now its OWN. The sink is still a sink;
  # the server holding its node key is no longer controlplane.tailscale.com
  # but headscale on 10.42.0.1. This SUPERSEDES #233, whose design had the
  # NAS and the coordinator both on official tailscale.com.
  #
  # Two consequences worth stating where the old comment stood:
  #   - "Login is interactive, no authkey secret lands on the appliance" is
  #     now "the key is minted at runtime by the headscale on this very box
  #     and lives only in /run" — the property that mattered (no credential
  #     at rest on the appliance, no new agenix door) is preserved, by a
  #     different and strictly more automatic mechanism.
  #   - "the advertised route must be APPROVED once in the Tailscale admin
  #     console" becomes `headscale nodes approve-routes` on this box. There
  #     is no admin console any more; there is a policy file in git.
  #
  # The coordinator does NOT follow. It keeps official tailscale.com,
  # always-connected-but-idle, as the EMERGENCY RAIL — coordinator + Freebox
  # is the off-NAS escape hatch, and an escape hatch that lives on the box
  # that might be the thing failing is not one. It needs no code change to
  # stay that way (it inherits modules/common.nix's defaults) and it must not
  # be "cleaned up" because headscale exists now.
  #
  # Every knob — useRoutingFeatures, both flag lists, the authKeyFile, the
  # enroll unit, the firewall doors — lives in ./headscale.nix so that the
  # server and this box's membership in it cannot drift apart. Read that file
  # before touching anything tailnet-shaped on this host.
  myNas.headscale.enable = true;

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
  # ws5 — flipped 2026-08-21 per the runbook in ./attic.nix: state rsynced
  # from the coordinator with atticd stopped, signing key verified intact,
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

  # ── /nix on the M.2 (#232) ──────────────────────────────────────────────
  # Flipped after the runbook in ./nix-on-nvme.nix was walked on the real
  # hardware: store rsync'd with -aHAX, verified, `nixos-rebuild boot`, and a
  # SUPERVISED reboot with a console on the HDMI corner. Never flip this
  # remotely — /nix is a neededForBoot mount and a mistake does not degrade,
  # it means the house router does not come up.
  myNas.nixOnNvme.enable = true;

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
