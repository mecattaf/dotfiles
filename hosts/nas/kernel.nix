{ freshPkgs, ... }:
# Follow the fleet's current kernel series (Tom, 2026-10-23, #584).
# The NAS keeps its stable userspace; kernel point releases come from freshPkgs.
{
  boot.kernelPackages = freshPkgs.linuxPackages_7_3;
}
