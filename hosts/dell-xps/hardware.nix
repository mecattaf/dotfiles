{ lib, modulesPath, ... }:
# ⚠️ PLACEHOLDER — regenerate ON the real machine. Evaluates only; will NOT boot as-is.
# At flash: `nixos-generate-config --no-filesystems` on the target, confirm `vmd`
# lands in availableKernelModules (XPS 13 9315 commonly ships Intel VMD ON, which
# hides the NVMe — the exact failure the duo hit), then overwrite this file.
# See docs/dell-xps-flash.md.
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "vmd" # Intel VMD — the NVMe hides behind it (duo needed this; XPS likely too)
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
