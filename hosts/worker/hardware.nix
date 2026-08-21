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
    # Not decoration: thunderbolt0 is this host's fallback rail to the
    # coordinator (10.99.0.2 <-> 10.99.0.1) and the path the reintegration
    # deploy itself travels over.
    "thunderbolt"
  ];
  boot.kernelModules = [ "kvm-amd" ];
  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
