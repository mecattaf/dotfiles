{
  pkgs,
  lib,
  self,
}:
let
  testUuid = "11111111-2222-4333-8444-555555555555";
  base = self.nixosConfigurations.nas;
  placeholder =
    (base.extendModules {
      modules = [ { myNas.homeDisk.partUuid = lib.mkForce "VERIFY-HOME-PARTUUID"; } ];
    }).config;
  nas =
    (base.extendModules {
      modules = [ { myNas.homeDisk.partUuid = lib.mkForce testUuid; } ];
    }).config;
  home = nas.fileSystems."/home";
  snapshots = nas.fileSystems."/mnt/home-snapshots";
  fast = nas.fileSystems."/mnt/fast";
  fanxiang = "/dev/disk/by-id/nvme-Fanxiang_S500Pro_256GB_26040259615000015";
  disk = nas.myNas.homeDisk.device;
in
assert home.device == "/dev/disk/by-partuuid/${testUuid}";
assert home.fsType == "btrfs" && !home.neededForBoot;
assert lib.all (option: lib.elem option home.options) [
  "subvol=@home"
  "compress=zstd:1"
  "noatime"
  "nofail"
  "x-systemd.device-timeout=10s"
];
assert snapshots.device == home.device && snapshots.fsType == "btrfs";
assert !snapshots.neededForBoot;
assert lib.all (option: lib.elem option snapshots.options) [
  "subvol=@snapshots"
  "noatime"
  "nofail"
];
assert lib.elem "/home" nas.systemd.services."user@1000".unitConfig.RequiresMountsFor;
assert lib.hasInfix "RequiresMountsFor=/home" nas.systemd.units."user@1000.service".text;
assert nas.systemd.units."user@1000.service".overrideStrategy == "asDropinIfExists";
assert nas.disko.devices.disk.journal.device == fanxiang;
assert nas.disko.devices.disk.journal.content.partitions.journal.content.mountpoint == "/mnt/fast";
assert
  fast.device == "/dev/disk/by-partlabel/disk-journal-journal"
  && fast.fsType == "ext4"
  && fast.neededForBoot;
assert nas.fileSystems."/nix".device == "/mnt/fast/nix";
assert nas.fileSystems."/nix".neededForBoot;
assert nas.fileSystems."/nix".depends == [ "/mnt/fast" ];
assert !(nas.disko.devices.disk ? home);
assert lib.all (fs: fs.device != "${disk}-part1") (lib.attrValues nas.fileSystems);
assert lib.all (device: lib.any (watch: watch.device == device) nas.services.smartd.devices) [
  fanxiang
  disk
  nas.myNas.storage.smartDevice
];
# Ensure filling the UUID discharges every NAS assertion, while an explicit
# placeholder still triggers the deployment guard. Does not build a toplevel.
assert lib.all (entry: entry.assertion) nas.assertions;
assert lib.any (
  entry: !entry.assertion && lib.hasInfix "VERIFY-HOME-PARTUUID" entry.message
) placeholder.assertions;
pkgs.runCommand "nas-home-disk"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.bash
      pkgs.rsync
      pkgs.shellcheck
    ];
    MIGRATE_SOURCE = ../../pkgs/nas-home-migrate;
  }
  ''
    shellcheck "$MIGRATE_SOURCE/migrate.sh"
    ${lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.nas-home-migrate} --help > /dev/null
    python3 ${./test_dry_run.py}
    touch "$out"
  ''
