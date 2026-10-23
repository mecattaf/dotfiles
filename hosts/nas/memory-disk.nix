{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.myNas.memoryDisk;
  device = "/dev/disk/by-id/nvme-Fanxiang_S500Pro_256GB_26040259615000015";
  partition = "${device}-part1";
  mountUnit = "${utils.escapeSystemdPath cfg.mountPoint}.mount";
in
{
  options.myNas.memoryDisk = {
    enable = lib.mkEnableOption "the repurposed 256GB Screenpipe/CUA recording and memory volume";
    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/agent-memory";
      description = "Reserved recording/log destination; no capture application is installed or started.";
    };
  };
  config = lib.mkMerge [
    {
      # A reservation, not a backup or snapshot target. Gate remains off while
      # the old fast tier still contains live /nix and service state.
      environment.etc."fleet/agent-memory-reservation.json".source =
        (pkgs.formats.json { }).generate "agent-memory-reservation.json"
          {
            inherit device;
            serial = "26040259615000015";
            mountPoint = cfg.mountPoint;
            enabled = cfg.enable;
            purpose = "Screenpipe/CUA recording, memory and log files";
            prerequisites = "Verified move and successful boot of all previous fast state on the 500GB primary; then attended reformat with label agent-memory";
          };
    }
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.myNas.homeDisk.layout == "shared-btrfs";
          message = "Release the 256GB memory gate only after moving /mnt/fast onto the 500GB shared pool.";
        }
      ];
      fileSystems.${cfg.mountPoint} = {
        device = partition;
        fsType = "ext4";
        options = [
          "noatime"
          "nofail"
          "x-systemd.device-timeout=10s"
        ];
      };
      systemd.services.nas-memory-disk-identity = {
        description = "Refuse the memory mount until the serial and repurpose label match";
        requiredBy = [ mountUnit ];
        before = [ mountUnit ];
        after = [ "${utils.escapeSystemdPath partition}.device" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -eu
          test "$(${pkgs.util-linux}/bin/lsblk --nodeps --noheadings --raw --output SERIAL ${device})" = 26040259615000015
          test "$(${pkgs.util-linux}/bin/blkid -s LABEL -o value ${partition})" = agent-memory
        '';
      };
    })
  ];
}
