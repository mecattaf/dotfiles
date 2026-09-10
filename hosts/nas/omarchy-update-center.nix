{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myNas.omarchyUpdateCenter;
  publisher = pkgs.writeShellApplication {
    name = "omarchy-update-publisher-internal";
    runtimeInputs = [
      config.nix.package
      pkgs.attic-client
      pkgs.openssh
      pkgs.git
      pkgs.python3
    ];
    text = ''
      export PATH="$PATH:/run/current-system/sw/bin"
      exec python3 ${./omarchy-update-publish.py} "$@"
    '';
  };
  cli = pkgs.writeShellApplication {
    name = "omarchy-update-publish";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
    ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo 'Run with sudo: omarchy-update-publish --source GIT --revision COMMIT --notes-file FILE [--devices xps zenbook-duo]' >&2
        exit 1
      fi
      exec systemd-run --unit=omarchy-update-publish --collect --wait --pipe \
        --property=Type=exec --property=RuntimeMaxSec=8h \
        --property=Nice=19 --property=CPUWeight=20 --property=MemoryMax=12G \
        --property=KillMode=control-group --property=TimeoutStopSec=2min \
        ${lib.getExe publisher} "$@"
    '';
  };
in
{
  options.myNas.omarchyUpdateCenter = {
    enable = lib.mkEnableOption "manual signed Omarchy offers and private fleet distribution";
    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "100.64.0.1";
      description = "NAS address on its independent Headscale fleet network.";
    };
    interface = lib.mkOption {
      type = lib.types.str;
      default = "tailscale0";
      description = "Headscale interface, constrained additionally by the fleet ACL.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8091;
    };
    keepalive.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Daily no-build refresh of current and previous signed closures in Attic.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.myNas.attic.enable;
        message = "Omarchy update publication requires the existing NAS Attic cache and signing key.";
      }
    ];
    environment.systemPackages = [ cli ];
    systemd.tmpfiles.rules = [
      "d /var/lib/omarchy-update-center 0755 root root -"
      "d /var/lib/omarchy-update-center/private 0700 root root -"
      "d /var/lib/omarchy-update-center/public 0755 root root -"
      "d /var/lib/omarchy-update-center/public/releases 0755 root root -"
      "d /var/lib/omarchy-update-center/roots 0700 root root -"
    ];
    services.nginx = {
      enable = true;
      virtualHosts."omarchy-updates" = {
        listen = [
          {
            addr = cfg.listenAddress;
            port = cfg.port;
          }
        ];
        root = "/var/lib/omarchy-update-center/public/current";
        locations."= /manifest.json".extraConfig = ''
          default_type application/json;
          add_header Cache-Control "no-store" always;
          try_files /manifest.json =404;
        '';
        locations."= /manifest.json.sig".extraConfig = ''
          default_type text/plain;
          add_header Cache-Control "no-store" always;
          try_files /manifest.json.sig =404;
        '';
        locations."/".return = "404";
      };
    };
    # The fleet address can arrive after network-online; retry binding it.
    systemd.services.nginx = {
      unitConfig.StartLimitIntervalSec = lib.mkForce 0;
      serviceConfig.Restart = lib.mkForce "on-failure";
      serviceConfig.RestartSec = "10s";
    };
    networking.firewall.extraInputRules = ''
      iifname "${cfg.interface}" ip daddr ${cfg.listenAddress} tcp dport { 8080, ${toString cfg.port} } accept comment "Headscale Omarchy cache and signed offers"
    '';
    systemd.services.omarchy-update-keepalive = {
      description = "Keep offered Omarchy closures in Attic without building or activating";
      after = [ "atticd.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe publisher} --keepalive";
        TimeoutStartSec = "2h";
        TimeoutStopSec = "2min";
        Nice = 19;
        CPUWeight = 20;
        MemoryMax = "2G";
      };
    };
    systemd.timers.omarchy-update-keepalive = lib.mkIf cfg.keepalive.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "04:30";
        Persistent = false;
        RandomizedDelaySec = "15min";
      };
    };
  };
}
