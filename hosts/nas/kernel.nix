{ freshPkgs, ... }:
# Tom, 2026-10-23: the NAS shares the current fleet kernel. Stable userspace
# does not freeze the kernel; all four hosts follow nixpkgs-fresh 7.2.y.
{
  boot.kernelPackages = freshPkgs.linuxPackages_7_2;
}
