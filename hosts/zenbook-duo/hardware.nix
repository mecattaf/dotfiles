{ config, lib, pkgs, modulesPath, ... }:
# Generated on the live Zenbook Duo (UX8406) via `nixos-generate-config --no-filesystems`
# during the jul5 flash — real, not a placeholder. Filesystems come from ./disko.nix,
# so no fileSystems entries here (worker pattern). Note the `vmd` initrd module (Intel
# VMD — the NVMe hides behind it) and the Meteor Lake NPU.
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "vmd" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.npu.enable = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
