{ ... }:
# ─── Where nix builds, and what it does when the eMMC runs out ─────────────
# 2026-10-23: agent-offload.nix sets zero local build jobs and sends builds
# to the Strix pair. Retain these scratch/store safeguards for orchestration.
#
# THE DEVICE FACT this box kept getting wrong (corrected 2026-08-22; the
# table is as of 2026-11-10, O1):
#
#   mmcblk0   57G  eMMC         →  /boot, /     ← the SMALLEST, SLOWEST device
#   nvme0n1  1TB   WD SN7100    →  one btrfs: @home → /home, @fast → /mnt/fast
#                                  (/nix bound from @fast/nix, attic, the remote
#                                  journal); boot-critical (./home-disk.nix)
#   nvme1n1  256G  Fanxiang     →  /mnt/immich  (Immich's PostgreSQL and
#                                  generated media, ./immich-disk.nix)
#   sda      3.7T  WD Red HDD   →  /mnt/nas
#
# In 2026-08 the 256G was /mnt/fast and held /nix; the 1TB took that role at
# the 2026-10-25 home cutover.
#
# `/` is the eMMC. It is not the M.2. Several modules were written as though
# "root" and "the 256GB M.2" were the same disk (./attic.nix's header says so
# in as many words), and the consequence is that the fleet's entire build and
# cache plane landed on 57G of eMMC while 186G of NVMe sat 17% used.
#
# This eMMC has now filled TWICE:
#   1. The first update-center run, with model-weight FODs — fixed by keeping
#      the whole weight plane out of nix: the Library in ./models.nix, working
#      copies through local-models-borrow (../../modules/local-models.nix).
#   2. 2026-08-22, found at 100% with ZERO bytes free and update-center in
#      failed state: "error: write of 26 bytes: No space left on device",
#      build FAILED for worker and zenbook-duo. 18G of it was atticd's state
#      (moved to the NVMe in ./attic.nix, same commit as this file).
#
# Twice is a pattern, and the pattern is that a device this small cannot be
# both the OS disk and a three-host build farm without help. This file is the
# help. It does NOT relocate /nix itself: the store must be present for the
# machine to boot at all, /mnt/fast is a budget NVMe mounted `nofail`
# precisely because it is treated as expendable (./disko.nix), and making the
# house router unbootable on that disk's failure is a far worse trade than a
# tight eMMC. So the store stays put and we move what does not need to be
# there — the scratch — and teach nix to clean up before it dies.
# Superseded 2026-08-22 by ./nix-on-nvme.nix; the pool is boot-critical.
{
  systemd.tmpfiles.rules = [
    # Build scratch on the NVMe. If /mnt/fast is absent this silently lands on
    # the eMMC again — degraded, not broken, which is the right failure for
    # scratch (contrast ./attic.nix, where the same silence would forge a new
    # signing key and so is a hard RequiresMountsFor instead).
    "d /mnt/fast/nix-build 0755 root root -"
  ];

  nix.settings = {
    # A closure build unpacks and links its inputs in the build dir before
    # anything lands in the store, so the transient peak — not the finished
    # closure — is what actually burst this disk. Nix 2.34 has a first-class
    # setting for it; no nix-daemon TMPDIR override needed.
    build-dir = "/mnt/fast/nix-build";

    # The self-heal that would have prevented the 2026-08-22 incident outright.
    # When free space on the STORE's filesystem drops below min-free mid-build,
    # nix pauses and collects until max-free is available, instead of running
    # the disk to 0 and dying with ENOSPC. This is nix's own in-build GC and it
    # only ever removes unreachable paths — it cannot touch a live generation,
    # and it is emphatically NOT `-d` (see ../../modules/gc-retention.nix for
    # why that flag is banned on this fleet).
    #
    # Deliberately scoped to this host and not to the fleet: the strix
    # and worker have roomy NVMe roots where the weekly sweep in
    # gc-retention.nix is sufficient, and only this host ever ran a nightly
    # three-host build farm on 57G of eMMC (the update center, since removed).
    min-free = 5368709120; # 5 GiB — start collecting
    max-free = 21474836480; # 20 GiB — collect until this much is free
  };
}
