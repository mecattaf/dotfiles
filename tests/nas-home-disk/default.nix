{
  pkgs,
  lib,
  self,
}:
let
  base = self.nixosConfigurations.nas;
  invalid =
    (base.extendModules {
      modules = [ { myNas.homeDisk.device = lib.mkForce "/dev/disk/by-id/nvme-wrong-serial"; } ];
    }).config;
  nas = base.config;
  legacy =
    (base.extendModules { modules = [ { myNas.homeDisk.layout = lib.mkForce "legacy-split"; } ]; })
    .config;
  home = nas.fileSystems."/home";
  snapshots = nas.fileSystems."/mnt/home-snapshots";
  fast = nas.fileSystems."/mnt/fast";
  fanxiang = "/dev/disk/by-id/nvme-Fanxiang_S500Pro_256GB_26040259615000015";
  disk = nas.myNas.homeDisk.device;
  # O1 PR-1 (hosts/nas/storage-alerts.nix): trip point per mount.
  diskAlerts = {
    disk-root = 75;
    disk-boot = 80;
    disk-pool = 85;
    disk-immich = 85;
    disk-hdd = 92;
  };
  alerts = nas.myTripwire;
  tripwireUnit = name: nas.systemd.services."tripwire-${name}";
  envName = lib.replaceStrings [ "-" ] [ "_" ];
  # O1 (2026-11-10): /var and /tmp onto the pool, evaluated in both states so
  # these assertions outlive the flip commit.
  systemOffEmmc =
    enable:
    (base.extendModules { modules = [ { myNas.systemOffEmmc.enable = lib.mkForce enable; } ]; }).config;
  offEmmc = systemOffEmmc true;
  onEmmc = systemOffEmmc false;
  offVar = offEmmc.fileSystems."/var";
  offTmp = offEmmc.fileSystems."/tmp";
in
assert home.device == "${disk}-part1";
assert disk == "/dev/disk/by-id/nvme-WD_BLACK_SN7100_1TB_26051Y809195";
assert !(base.options.myNas.homeDisk ? partUuid);
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
assert nas.systemd.units."user@1000.service".overrideStrategy == "asDropin";
assert nas.disko.devices.disk.journal.device == fanxiang;
assert nas.disko.devices.disk.journal.content.partitions.journal.content.mountpoint == "/mnt/fast";
assert
  fast.device == home.device
  && fast.fsType == "btrfs"
  && builtins.elem "subvol=@fast" fast.options
  && fast.neededForBoot;
# The systemd initrd mounts only x-initrd.mount entries; /nix binds from @fast.
assert lib.elem "x-initrd.mount" fast.options;
assert nas.fileSystems."/nix".device == "/mnt/fast/nix";
assert nas.fileSystems."/nix".neededForBoot;
assert nas.fileSystems."/nix".depends == [ "/mnt/fast" ];
assert !(nas.disko.devices.disk ? home);
# The 256GB Fanxiang is Immich's fast tier: PostgreSQL and generated media.
assert nas.myNas.immichDisk.enable;
assert nas.fileSystems."/mnt/immich".device == "${fanxiang}-part1";
assert nas.fileSystems."/mnt/immich".fsType == "ext4";
assert lib.elem "nofail" nas.fileSystems."/mnt/immich".options;
assert lib.hasInfix "= immich" nas.systemd.services.nas-immich-disk-identity.script;
assert lib.hasInfix "26040259615000015" nas.systemd.services.nas-immich-disk-identity.script;
assert lib.hasPrefix "/mnt/immich/postgresql/" nas.services.postgresql.dataDir;
assert lib.elem "/mnt/immich" nas.systemd.services.postgresql.unitConfig.RequiresMountsFor;
assert lib.elem "/mnt/immich" nas.systemd.services.immich-server.unitConfig.RequiresMountsFor;
assert legacy.fileSystems."/home".device == "${disk}-part2";
assert legacy.fileSystems."/mnt/fast".fsType == "ext4";
assert lib.all (device: lib.any (watch: watch.device == device) nas.services.smartd.devices) [
  fanxiang
  disk
  nas.myNas.storage.smartDevice
];
# The real configuration now evaluates without a UUID override; an inconsistent
# by-id / serial still fails the identity assertion. No hardware is accessed.
assert lib.all (entry: entry.assertion) nas.assertions;
assert lib.any (
  entry: !entry.assertion && lib.hasInfix "verified serial" entry.message
) invalid.assertions;
# O1 PR-1 storage alerts: one usage tripwire per NAS mount, re-arming 5 points
# lower and re-marking daily; one presence tripwire over every declared mount
# except /; the local journal cap declared at journald's implicit 4G.
assert lib.all (
  name:
  alerts.${name}.enable
  && alerts.${name}.threshold == diskAlerts.${name}
  && alerts.${name}.rearm == diskAlerts.${name} - 5
  && alerts.${name}.renotifySeconds == 86400
  && alerts.${name}.intervalSeconds == 600
  && nas.systemd.timers ? "tripwire-${name}"
) (lib.attrNames diskAlerts);
assert alerts.nas-mounts.enable && alerts.nas-mounts.threshold == 1;
assert alerts.nas-mounts.rearm == 1 && alerts.nas-mounts.renotifySeconds == 86400;
assert nas.systemd.timers ? tripwire-nas-mounts;
assert lib.all (mount: lib.elem mount nas.myNas.storageAlerts.requiredMounts) [
  "/boot"
  "/home"
  "/mnt/fast"
  "/nix"
  "/mnt/immich"
  "/mnt/nas"
  "/var/log/journal/remote"
  "/var/lib/private/atticd"
];
assert !(lib.elem "/" nas.myNas.storageAlerts.requiredMounts);
# No journal size cap (Tom, 2026-11-10), local or remote.
assert lib.hasInfix "SystemMaxUse=16T" nas.services.journald.extraConfig;
assert lib.hasInfix "SystemMaxFiles=1000000" nas.services.journald.extraConfig;
assert nas.services.journald.remote.settings.Remote.MaxUse == "16T";
assert nas.services.journald.remote.settings.Remote.MaxFiles == 1000000;
# O1: merging the gate OFF changes no mount (delete these four lines in the flip commit).
assert !nas.myNas.systemOffEmmc.enable;
assert !(nas.fileSystems ? "/var") && !(nas.fileSystems ? "/tmp");
assert !nas.boot.tmp.cleanOnBoot;
assert nas.system.switch.inhibitors.nas-var-tmp-backing == "eMMC root";
assert
  !(onEmmc.fileSystems ? "/var") && !(onEmmc.fileSystems ? "/tmp") && !onEmmc.boot.tmp.cleanOnBoot;
# Gate on: @var is boot-critical and initrd-mounted, @tmp is not.
assert offVar.device == "${disk}-part1" && offVar.fsType == "btrfs";
assert offVar.neededForBoot;
assert lib.all (option: lib.elem option offVar.options) [
  "subvol=@var"
  "compress=zstd:1"
  "noatime"
  "x-initrd.mount"
];
assert !(lib.elem "nofail" offVar.options);
assert offTmp.device == offVar.device && offTmp.fsType == "btrfs" && !offTmp.neededForBoot;
assert lib.all (option: lib.elem option offTmp.options) [
  "subvol=@tmp"
  "nofail"
  "x-systemd.before=local-fs.target"
];
assert !(lib.elem "x-initrd.mount" offTmp.options);
assert offEmmc.boot.tmp.cleanOnBoot;
assert lib.elem "D! /tmp 1777 root root" offEmmc.systemd.tmpfiles.rules;
# A live switch between the two states is refused; the existing binds stay.
assert
  offEmmc.system.switch.inhibitors.nas-var-tmp-backing
  != onEmmc.system.switch.inhibitors.nas-var-tmp-backing;
assert
  offEmmc.fileSystems."/var/lib/private/atticd" == onEmmc.fileSystems."/var/lib/private/atticd";
assert
  offEmmc.fileSystems."/var/log/journal/remote" == onEmmc.fileSystems."/var/log/journal/remote";
assert offEmmc.fileSystems."/nix" == onEmmc.fileSystems."/nix";
# nas-mounts derives its list from fileSystems, so it watches the new mounts.
assert lib.all (mount: lib.elem mount offEmmc.myNas.storageAlerts.requiredMounts) [
  "/var"
  "/tmp"
];
assert !(lib.elem "/var" onEmmc.myNas.storageAlerts.requiredMounts);
assert lib.all (entry: entry.assertion) offEmmc.assertions;
pkgs.runCommand "nas-home-disk"
  (
    {
      nativeBuildInputs = [
        pkgs.python3
        pkgs.bash
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.rsync
        pkgs.shellcheck
        pkgs.util-linux
      ];
      MIGRATE_SOURCE = ../../pkgs/nas-home-migrate;
      STORAGE_ALERTS_TEST = ./storage_alerts.sh;
      TRIPWIRE_POLL = (tripwireUnit "disk-root").serviceConfig.ExecStart;
      FAILURE_MARKER_RECONCILER = ../../modules/failure-marker-reconcile.sh;
      FAILURE_MARKER_REPORTER = ../../modules/failure-marker-report.sh;
      USAGE_NAMES = lib.concatStringsSep " " (lib.attrNames diskAlerts);
    }
    // lib.listToAttrs (
      lib.concatMap (name: [
        (lib.nameValuePair "SENSOR_${envName name}" (tripwireUnit name).environment.TRIPWIRE_SENSOR)
        (lib.nameValuePair "ONFIRE_${envName name}" (tripwireUnit name).environment.TRIPWIRE_ONFIRE)
      ]) (lib.attrNames diskAlerts ++ [ "nas-mounts" ])
    )
  )
  ''
    shellcheck "$MIGRATE_SOURCE/migrate.sh"
    ${lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.nas-home-migrate} --help > /dev/null
    python3 ${./test_dry_run.py}
    shellcheck "$STORAGE_ALERTS_TEST"
    bash "$STORAGE_ALERTS_TEST"
    touch "$out"
  ''
