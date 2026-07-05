{ lib, modulesPath, ... }:
# Worker hardware. Filesystems come from ./disko.nix (nixos-anywhere partitions the
# NVMe). initrd modules cover the WD_BLACK NVMe + TB3; verified over TB3 pre-flight
# 2026-07-05. Confirm the module set against `nixos-generate-config` after first boot.
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
