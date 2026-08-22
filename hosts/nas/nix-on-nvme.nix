{ config, lib, ... }:
# ─── /nix onto the 256G M.2 — GATE OFF, runbook below ───────────────────────
#
# THE CAPACITY PROBLEM, stated plainly. ./nix-builds.nix moved build scratch
# to the NVMe and added min-free/max-free, and that was NOT ENOUGH — it
# treated a capacity problem as a hygiene problem. Measured 2026-08-22 with
# min-free confirmed live in the daemon (min-free=5G, max-free=20G,
# min-free-check-interval=5) while update-center built the coordinator:
#
#   08:09:09 free=4188M     08:10:33 free=2067M
#   08:09:45 free=4103M     08:10:45 free=1373M
#   08:10:09 free=3616M     08:10:57 free= 824M
#
# It sailed through the 5G floor without collecting a byte, and the build was
# killed by hand at 669M. The reason is structural: min-free deletes only
# UNREACHABLE paths, and every output and dependency of an in-flight `nix
# build` is rooted by that build. The instant it was killed, 23,965 paths
# became dead. min-free defends against accumulated garbage; it cannot
# conjure space for a working set that does not fit.
#
# And it does not fit. 57G of eMMC has to hold the OS, the store, and the
# transient peak of THREE desktop-class fleet closures every night. The M.2
# next to it was 25% used with 168G free.
#
# Which is also the endurance argument: eMMC has markedly worse write
# endurance than an NVMe with a real controller, and the nightly build farm
# is the most write-heavy thing on this box. It is on the wrong disk twice
# over.
#
# ── WHY THIS LANDS OFF, and must not be flipped remotely ────────────────────
# /nix must be mounted before stage-2 init — the init IS a store path. So
# this is a neededForBoot mount, it takes effect ONLY at boot, and a mistake
# does not degrade: the machine does not come up. On the box that is the
# house router, DHCP, DNS and the tailnet subnet router, "does not come up"
# means no internet, and no remote access to repair it.
#
# The failure is also DELAYED, which is what makes flipping it casually so
# bad: switch succeeds, everything keeps running from the old /nix, and the
# breakage waits for the next reboot — which may be an unattended power cut
# weeks later, with nobody home. That is strictly worse than the full disk it
# fixes. It flips with hands on the box, per #232.
#
# ── RUNBOOK (#232) ─────────────────────────────────────────────────────────
#   1. Confirm room:  df -h /nix /mnt/fast     # need ~2x the store, NVMe side
#   2. Quiesce:       sudo systemctl stop update-center atticd
#                     sudo nix-store --gc      # NEVER -d (modules/gc-retention.nix)
#   3. Copy, preserving hardlinks — auto-optimise-store means the store is
#      full of them and -H is the difference between 30G and far more:
#        sudo mkdir -p /mnt/fast/nix
#        sudo rsync -aHAX --info=progress2 /nix/ /mnt/fast/nix/
#   4. Verify before trusting it:
#        sudo diff -r --no-dereference /nix/store /mnt/fast/nix/store | head
#        du -sh /nix /mnt/fast/nix        # sizes should be close
#   5. Flip this gate to true, then `nixos-rebuild boot` (NOT switch — boot
#      stages the generation without trying to remount /nix under a running
#      system, which is the one thing that cannot work).
#   6. REBOOT WITH HANDS ON THE BOX and a screen on the HDMI corner.
#   7. Verify:  findmnt /nix && df -h /nix && systemctl --failed
#   8. Only once booted clean: reclaim the eMMC copy.
#        sudo mv /nix.old /nix.delete-me && sudo rm -rf /nix.delete-me
#      (Do NOT delete in the same session that flips the gate — the old copy
#      is the entire rollback story if step 6 goes wrong.)
{
  options.myNas.nixOnNvme.enable = lib.mkEnableOption
    "back /nix with the 256G M.2 instead of the 57G eMMC (REBOOT-ONLY, see #232)";

  config = lib.mkIf config.myNas.nixOnNvme.enable {
    # Both are neededForBoot: the initrd must mount /mnt/fast before it can
    # bind the store out of it. Note this deliberately CONTRADICTS the
    # `nofail` on /mnt/fast in ./disko.nix, and the contradiction is the whole
    # point — once the store lives there, that disk stops being expendable and
    # a boot without it is not a degraded boot, it is no boot at all. Flipping
    # this gate is therefore also a decision to treat the M.2 as critical
    # hardware and to keep the eMMC copy until it has earned that trust.
    fileSystems."/mnt/fast".neededForBoot = true;
    fileSystems."/nix" = {
      device = "/mnt/fast/nix";
      fsType = "none";
      options = [ "bind" ];
      neededForBoot = true;
      depends = [ "/mnt/fast" ];
    };
  };
}
