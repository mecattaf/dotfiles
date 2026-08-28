{ lib, modulesPath, ... }:
# Module list reconciled against `nixos-generate-config --show-hardware-config`
# on the live coordinator (2026-07-11): the generator emits exactly
# nvme xhci_pci thunderbolt uas usbhid sd_mod. Dropped the earlier guesses
# `ahci` (no SATA root — root is nvme) and `usb_storage` (superseded by `uas`,
# the modern USB-Attached-SCSI driver the generator detects), added `uas`.
# Filesystems come from ./disko.nix (disk verified 2026-07-05).
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    # "thunderbolt" left the initrd 2026-08-29 (#241): the initrd's udev
    # coldplug bound the STOCK core before "Switching root" (08-21 boot
    # journal), which made it impossible for fn-rdma.nix's patched core to be
    # the first driver bound — the reference bring-up's one non-negotiable
    # rule. This box boots from NVMe; nothing in early boot needs a TB tunnel.
    "uas"
    "usbhid"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-amd" ];
  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
