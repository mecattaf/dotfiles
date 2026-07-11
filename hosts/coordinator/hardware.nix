{ lib, modulesPath, ... }:
# Module list reconciled against `nixos-generate-config --show-hardware-config`
# on the live coordinator (2026-07-11): the generator emits exactly
# nvme xhci_pci thunderbolt uas usbhid sd_mod. Dropped the earlier guesses
# `ahci` (no SATA root — root is nvme) and `usb_storage` (superseded by `uas`,
# the modern USB-Attached-SCSI driver the generator detects), added `uas`.
# Filesystems come from ./disko.nix (worker pattern; disk verified 2026-07-05).
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "uas"
    "usbhid"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-amd" ];
  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
