# Applied to ps4-dummy with extendModules, leaving the ordinary host unchanged.
# bootFiles is one paired, source-pinned psX kernel/initramfs/loader bundle.
{
  bootFiles ? null,
}:
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  selectedBootFiles = if bootFiles == null then config.system.build.ps4BootFiles else bootFiles;
in
{
  imports = [ (modulesPath + "/installer/sd-card/sd-image.nix") ];
  hardware.enableAllHardware = lib.mkForce false;

  image.baseName = "ps4-dummy-nixos";
  sdImage = {
    firmwarePartitionName = "PS4BOOT";
    firmwarePartitionID = "0x504e4958";
    firmwareSize = 512;
    rootVolumeLabel = "ps4-nixos";
    rootPartitionUUID = "5597a37d-8495-4941-82cf-8b830b481a1a";
    rootFilesystemCreator = ./make-btrfs-fs.nix;
    compressImage = false;
    # No automatic partition edits, including on a wrongly identified device.
    # Growth is a separately inspected, USB-only step after successful boot.
    expandOnBoot = false;
    populateFirmwareCommands = ''
      cp -r --no-preserve=mode,ownership ${selectedBootFiles}/. firmware/
      for file in bzImage initramfs.cpio.gz bootargs.txt vram.txt; do
        test -s "firmware/$file"
      done
      (cd firmware; find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
    '';
    populateRootCommands = ''
      mkdir -p files/sbin files/nix/var/nix/profiles files/etc
      printf '#!%s\nexec %s/init\n' ${pkgs.runtimeShell} ${config.system.build.toplevel} > files/sbin/init
      chmod 755 files/sbin/init
      ln -s ${config.system.build.toplevel} files/nix/var/nix/profiles/system
      touch files/etc/NIXOS
    '';
  };
  fileSystems."/".fsType = lib.mkForce "btrfs";

  # The standard image module mounts this at /boot/firmware. ps4-dummy owns
  # /boot instead, so never declare two mounts of the same FAT filesystem.
  fileSystems."/boot/firmware".enable = lib.mkForce false;
}
