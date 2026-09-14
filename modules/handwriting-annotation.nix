{ config, lib, pkgs, ... }:
let
  cfg = config.services.handwriting-annotation;
  package = pkgs.callPackage ../pkgs/handwriting-annotation { };
  intakePackage = pkgs.callPackage ../pkgs/handwriting-intake { };
in {
  options.services.handwriting-annotation.enable = lib.mkEnableOption "private handwriting annotation";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ package intakePackage ];
    systemd.tmpfiles.rules = [ "d /var/lib/handwriting-intake 0700 tom users -" ];
    networking.hosts."127.0.0.1" = [ "handwriting.internal" ];
    networking.firewall.interfaces.wlp192s0.allowedTCPPorts = [ 443 ];
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 443 ];
    systemd.services.handwriting-annotation = {
      description = "Writer-confirmed handwriting annotation";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      # Import once explicitly. Updating/restarting the app never seeds, replaces,
      # or truncates tasks, the append-only review log, or evidence snapshots.
      unitConfig.ConditionPathExists = "/var/lib/handwriting-annotation/tasks.json";
      serviceConfig = {
        User = "tom";
        Group = "users";
        StateDirectory = "handwriting-annotation";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/handwriting-annotation";
        ExecStart = "${package}/bin/handwriting-annotation --state /var/lib/handwriting-annotation serve --port 8766 --trusted-origin https://handwriting.internal";
        Restart = "on-failure";
        RestartSec = 2;
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [ "/var/lib/handwriting-annotation" ];
      };
    };
    # Application-consistent export into the existing NAS documents tier.
    # That subvolume already has btrbk snapshots and the house cold mirror;
    # SQLite's online backup API is used by the app, never a copy of live WAL.
    systemd.services.handwriting-annotation-backup = {
      description = "Snapshot handwriting annotations onto the NAS documents tier";
      unitConfig = {
        ConditionPathExists = "/var/lib/handwriting-annotation/tasks.json";
        RequiresMountsFor = [ "/mnt/nas/documents" ];
      };
      serviceConfig = {
        Type = "oneshot";
        User = "tom";
        Group = "users";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [ "/var/lib/handwriting-annotation" "/mnt/nas/documents" ];
        ExecStart = pkgs.writeShellScript "handwriting-annotation-backup" ''
          set -eu
          # Trigger the automount, then refuse an unmounted local lookalike.
          cd /mnt/nas/documents
          ${pkgs.util-linux}/bin/findmnt -n -t nfs,nfs4 --target "$PWD" >/dev/null
          destination="$PWD/handwriting-annotation-backups"
          ${pkgs.coreutils}/bin/mkdir -p "$destination"
          stamp=$(${pkgs.coreutils}/bin/date -u +%Y%m%dT%H%M%S.%NZ)
          exec ${package}/bin/handwriting-annotation \
            --state /var/lib/handwriting-annotation snapshot --output "$destination/$stamp"
        '';
      };
    };
    systemd.timers.handwriting-annotation-backup = {
      description = "Daily handwriting annotation snapshot";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
    };
    # Manual one-capture pilot: installing the CLI does not scan or OCR the inbox.
    # Its independent source/request/export evidence joins the same NAS tier.
    systemd.services.handwriting-intake-backup = {
      description = "Snapshot Huion intake evidence onto the NAS documents tier";
      unitConfig = {
        ConditionPathExists = "/var/lib/handwriting-intake/intake.sqlite3";
        RequiresMountsFor = [ "/mnt/nas/documents" ];
      };
      serviceConfig = {
        Type = "oneshot";
        User = "tom";
        Group = "users";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [ "/var/lib/handwriting-intake" "/mnt/nas/documents" ];
        Restart = "on-failure";
        RestartSec = "5m";
        ExecStart = pkgs.writeShellScript "handwriting-intake-backup" ''
          set -eu
          cd /mnt/nas/documents
          ${pkgs.util-linux}/bin/findmnt -n -t nfs,nfs4 --target "$PWD" >/dev/null
          destination="$PWD/handwriting-intake-backups"
          ${pkgs.coreutils}/bin/mkdir -p "$destination"
          stamp=$(${pkgs.coreutils}/bin/date -u +%Y%m%dT%H%M%S.%NZ)
          exec ${intakePackage}/bin/handwriting-intake \
            --state /var/lib/handwriting-intake snapshot --output "$destination/$stamp"
        '';
      };
    };
    systemd.timers.handwriting-intake-backup = {
      description = "Daily Huion intake evidence snapshot";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
    };
    services.caddy.virtualHosts."http://handwriting.internal".extraConfig = ''
      redir https://handwriting.internal{uri} 308
    '';
    services.caddy.virtualHosts."https://handwriting.internal".extraConfig = ''
      tls internal
      reverse_proxy 127.0.0.1:8766
    '';
  };
}
