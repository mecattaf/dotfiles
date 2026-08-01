{ lib, modulesPath, ... }:
# PRE-FLASH PLACEHOLDER. Replace this file with the live output of
# nixos-generate-config --no-filesystems before the draft PR becomes mergeable.
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "ahci"
    "mmc_block"
    "nvme"
    "sd_mod"
    "sdhci_pci"
    "usb_storage"
    "usbhid"
    "xhci_pci"
  ];
  boot.kernelModules = [ "kvm-amd" ];
  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
