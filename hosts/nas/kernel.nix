{ freshPkgs, ... }:
# D-54 keep-7.2 candidate (2026-10-25, provenance branch nas/d54-keep-72, never
# merged): the NAS cutover closure on Linux 7.2.12 instead of main's 7.3 series.
# 7.2.12 is one point release from the 7.2.10 kernel that the D-52 gen 86 boot
# proves on this board. Main follows 7.3 (Tom, 2026-10-23, #584); D-54 is Tom's.
# If D-54 picks keep-7.2, the fleet-wide "every host follows Linux 7.3" asserts
# (flake.nix, tests/cutover-integration, tests/nas-agent-host) need a NAS
# exception before this can merge; this branch only builds the closure.
{
  boot.kernelPackages = freshPkgs.linuxPackages_7_2;
}
