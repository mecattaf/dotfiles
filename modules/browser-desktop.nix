{ config, lib, pkgs, ... }:
let cfg = config.services.browser-desktop;
in {
  options.services.browser-desktop.enable = lib.mkEnableOption "the shared headless Sway browser desktop";
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.browser-desktop ];
    systemd.user.services.browser-desktop = {
      description = "Shared browser desktop (Sway and WayVNC)";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.browser-desktop}/bin/browser-desktop";
        Restart = "always";
        RestartSec = 3;
        KillMode = "control-group";
        TimeoutStopSec = 15;
        UMask = "0077";
      };
      unitConfig = {
        ConditionUser = "tom";
        StartLimitIntervalSec = 0;
      };
    };
    services.caddy.virtualHosts."http://browser.internal".extraConfig = ''
      # Share Caddy's existing listener and BE550/tailnet firewall policy.
      # A separate bind here would overlap its other :80 virtual hosts.
      handle /vnc {
        reverse_proxy 127.0.0.1:5901
      }
      handle_path /control/* {
        reverse_proxy 127.0.0.1:4782
      }
      handle_path /novnc/* {
        root * ${pkgs.browser-desktop.webRoot}
        file_server
      }
      handle {
        redir /novnc/vnc.html?autoconnect=1&path=/vnc&resize=scale&reconnect=1&reconnect_delay=2000 302
      }
    '';
  };
}
