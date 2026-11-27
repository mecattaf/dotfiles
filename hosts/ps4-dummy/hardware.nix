{
  config,
  lib,
  pkgs,
  ...
}:
let
  platform = pkgs.callPackage ../../pkgs/ps4-platform {
    inherit (config.myPs4) gpuBackingLimitMiB kernelVariant;
    rootLabel = "ps4-nixos";
  };
in
{
  # psX's payload provides the kernel and initramfs; its switch_root enters
  # the real /sbin/init placed in the USB image. NixOS subsequently maintains
  # that bridge to /nix/var/nix/profiles/system/init on each activation.
  boot.kernel.enable = false;
  boot.initrd.enable = false;
  boot.loader.initScript.enable = true;
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  # boot.kernel.enable=false omits NixOS's ordinary kernel/modules links.
  # Preserve the matching psX kernel modules explicitly; never pair this
  # root with modules from the stock NixOS or Strix kernel.
  system.modulesTree = [ platform.kernel ];
  system.systemBuilderCommands = ''
    ln -s ${config.system.modulesTree} "$out/kernel-modules"
  '';
  system.build.ps4BootFiles = platform.bootFiles;

  # Both labels are on the removable Linux medium. Nothing here describes or
  # formats the internal Sony partition table or its encrypted filesystems.
  fileSystems."/" = {
    device = "/dev/disk/by-label/ps4-nixos";
    fsType = "btrfs";
    options = [
      "noatime"
      "compress=zstd:1"
    ];
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/PS4BOOT";
    fsType = "vfat";
    options = [
      "noauto"
      "nofail"
      "umask=0077"
    ];
  };

  # Firmware/modules and the external loader's bootargs are packaged by the
  # separate ps4-platform integration. boot.kernelParams does not rewrite
  # PS4BOOT/bootargs.txt, so no memory/clock claim is hidden here.
  hardware.graphics.enable = true;
  hardware.graphics.package = pkgs.callPackage ../../pkgs/ps4-mesa { };
  hardware.graphics.enable32Bit = false;
}
