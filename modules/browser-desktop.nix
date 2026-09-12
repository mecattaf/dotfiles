{ config, lib, pkgs, ... }:
let cfg = config.services.browser-desktop;
in {
  options.services.browser-desktop.enable = lib.mkEnableOption "the shared headless Sway browser desktop";
  config = lib.mkIf cfg.enable {
    # Keep the local agent independent of tailnet split-DNS for .internal.
    # LAN clients resolve the same name through the NAS to 10.42.0.2.
    networking.hosts."127.0.0.1" = [ "browser.internal" ];
    environment.systemPackages = [ pkgs.browser-desktop ];
    systemd.user.services.browser-desktop = {
      description = "Shared browser desktop (Sway and WayVNC)";
      # Keep open browser windows through configuration updates. Compositor
      # changes take effect at reboot or an explicit service restart.
      restartIfChanged = false;
      serviceConfig = {
        ExecStart = "${pkgs.browser-desktop}/bin/browser-desktop";
        ExecStartPost = pkgs.writeShellScript "browser-desktop-ready" ''
          for attempt in {1..50}; do
            if (exec 3<>/dev/tcp/127.0.0.1/5901) 2>/dev/null; then exit 0; fi
            ${pkgs.coreutils}/bin/sleep 0.2
          done
          echo 'WayVNC did not start; restarting the desktop' >&2
          exit 1
        '';
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
    systemd.user.services.browser-desktop-menu = {
      description = "Chrome profile menu for the shared noVNC desktop";
      wantedBy = [ "default.target" ];
      after = [ "browser-desktop.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.browser-desktop}/bin/browser-desktop-menu";
        Restart = "on-failure";
        RestartSec = 3;
        TimeoutStopSec = 15;
        UMask = "0077";
      };
      unitConfig.ConditionUser = "tom";
    };
    networking.firewall.interfaces.wlp192s0.allowedTCPPorts = [ 443 ];
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 443 ];
    services.caddy.virtualHosts."http://browser.internal".extraConfig = ''
      redir https://browser.internal{uri} 308
    '';
    services.caddy.virtualHosts."https://browser.internal".extraConfig = ''
      tls internal
      # Share Caddy's existing listener and BE550/tailnet firewall policy.
      # A separate bind here would overlap its other :80 virtual hosts.
      handle /vnc {
        reverse_proxy 127.0.0.1:5901
      }
      handle_path /control/* {
        reverse_proxy 127.0.0.1:4782
      }
      handle_path /desktop/* {
        reverse_proxy 127.0.0.1:4784
      }
      handle_path /novnc/* {
        root * ${pkgs.browser-desktop.webRoot}
        file_server
      }
      handle {
        redir * /novnc/vnc.html?autoconnect=1&path=/vnc&resize=scale&reconnect=1&reconnect_delay=2000 302
      }
      # The per-task control server is intentionally absent while idle.
      handle_errors 502 {
        @idle path /control/state /state
        handle @idle {
          header Content-Type application/json
          respond `{"owner":"human","phase":"idle"}` 200
        }
        handle {
          respond "{err.status_text}" {err.status_code}
        }
      }
    '';
  };
}
