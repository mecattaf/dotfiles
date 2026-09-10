{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myNas.headscale.backup;
  backup = pkgs.writeShellApplication {
    name = "headscale-backup-verify";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      if [ "$#" -ne 1 ]; then
        echo 'Usage: sudo headscale-backup-verify /mnt/nas/services/headscale-backups/current' >&2
        exit 1
      fi
      exec python3 ${./headscale-backup.py} --verify "$1"
    '';
  };
in
{
  options.myNas.headscale.backup = {
    enable = lib.mkEnableOption "consistent private Headscale database and Noise identity backups on the NAS data disk";
    schedule.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Weekly backup timer; disabling leaves manual backup and verification available.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.myNas.headscale.enable;
        message = "Headscale backups require the NAS Headscale control plane.";
      }
    ];
    environment.systemPackages = [ backup ];
    # No tmpfiles rule here: it could create a backup directory on the root
    # disk before /mnt/nas mounts. The guarded backup script owns creation.
    systemd.services.headscale-backup = {
      description = "Snapshot and verify Headscale identity on the separate NAS data disk";
      after = [ "headscale.service" ];
      unitConfig = {
        RequiresMountsFor = [ "/mnt/nas" ];
        AssertPathIsMountPoint = "/mnt/nas";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.python3}/bin/python3 ${./headscale-backup.py} --config ${config.services.headscale.configFile} --policy ${./headscale-policy.hujson}";
        User = "root";
        Group = "root";
        UMask = "0077";
        TimeoutStartSec = "10min";
        MemoryMax = "256M";
        Nice = 19;
        CPUWeight = 20;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "/mnt/nas/services" ];
        # SQLite may need to open an existing shared-memory sidecar; the
        # read-only source connection does not modify live database rows.
        ReadOnlyPaths = [ "/var/lib/headscale" ];
      };
    };
    systemd.timers.headscale-backup = lib.mkIf cfg.schedule.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun *-*-* 08:30:00";
        Persistent = false;
        RandomizedDelaySec = "15min";
      };
    };
  };
}
