{ config, lib, modulesPath, ... }:
# Live hardware config, captured on the DXP2800 GT via
# `nixos-generate-config --no-filesystems --show-hardware-config` in the
# kexec installer on 2026-08-01 (issue #131). Two deliberate additions to the
# generated initrd module list:
#
#   - mmc_block: the generator omits it, but the root filesystem lives on the
#     eMMC — without the block driver the initrd cannot find /.
#   - sdhci_acpi is the live controller driver (AMDI0040), straight from the
#     generator; the pre-flash placeholder's sdhci_pci guess was wrong.
#
# Kexec-only quirk, recorded for future operators: a kexec that bypasses
# firmware leaves this eMMC stuck in HS400 and it re-inits with error -110;
# recover with `modprobe sdhci debug_quirks2=0x4` (drop 1.8V signaling)
# before reloading sdhci_acpi. Cold and firmware-mediated boots are clean.
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "sdhci_acpi"
    "mmc_block"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.enableRedistributableFirmware = lib.mkDefault true;
}
