{ lib, modulesPath, ... }:
# ⚠️ PLACEHOLDER module list — confirm against `nixos-generate-config` at flash time.
# Filesystems come from ./disko.nix (worker pattern; disk verified 2026-07-05).
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "thunderbolt"
  ];
  boot.kernelModules = [ "kvm-amd" ];
  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
