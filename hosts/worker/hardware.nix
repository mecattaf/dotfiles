{ lib, modulesPath, ... }:
# Worker hardware. Filesystems come from ./disko.nix. The module set below was
# written from the TB3 pre-flight (2026-07-05) and is RE-VERIFIED against the
# running box at the 2026-08-21 reintegration (#229): `thunderbolt` and `nvme`
# are both live in /proc/modules, the root device is the WD_BLACK SN7100 500GB
# ./disko.nix names, and the box has been booting on exactly this set for six
# weeks. Nothing to confirm after first boot any more — this IS the confirmed set.
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
    # "thunderbolt" left the initrd 2026-08-29 (#241): the initrd coldplug
    # bound the stock core before the root switch, so fn-rdma.nix's patched
    # core could never be first — the one non-negotiable rule. The rail this
    # entry served still comes up, just from stage 2; and since the #241
    # repoint, deploys dial the fleet identity (10.99.9.2), not this rail.
  ];
  boot.kernelModules = [ "kvm-amd" ];
  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
