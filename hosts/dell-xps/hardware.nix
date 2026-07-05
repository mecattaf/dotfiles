{ lib, modulesPath, ... }:
# ⚠️ PLACEHOLDER — regenerate ON the real machine. Evaluates only; will NOT boot as-is.
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-intel" ];
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;

  # Filesystems come from ./disko.nix (worker pattern).

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
