{ freshPkgs, ... }:
# Keep the kernel series validated on this hardware during the network move.
# Changing the appliance kernel is a separate compatibility and reboot decision.
{
  boot.kernelPackages = freshPkgs.linuxPackages_7_2;
}
