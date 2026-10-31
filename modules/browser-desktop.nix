{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.browser-desktop;
in
{
  options.services.browser-desktop = {
    enable = lib.mkEnableOption "the shared headless Sway browser desktop";
    frontDoor = {
      enable = lib.mkEnableOption "the Caddy front door for https://browser.internal (no desktop runs on this host)";
      backend = lib.mkOption {
        type = lib.types.str;
        default = "strix-coordinator";
        description = "Host that runs the browser desktop (WayVNC on 5901, menu on 4784).";
      };
    };
  };
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.networking.nftables.enable;
          message = "browser-desktop: the NAS-only extraInputRules need networking.nftables.enable.";
        }
        {
          assertion =
            let
              trusted = config.networking.firewall.trustedInterfaces;
            in
            !(builtins.elem "tailscale0" trusted)
            && !(builtins.any (
              i: lib.hasPrefix "vm" i || lib.hasPrefix "microvm" i || lib.hasPrefix "br" i
            ) trusted);
          message = "browser-desktop: a trusted tailscale0 or microvm interface would bypass the 10.42.0.1 source rule for WayVNC (no auth).";
        }
      ];
      # WayVNC has no authentication: bind all addresses, admit only the NAS.
      # Not the static 10.42.0.2: it comes from a NetworkManager profile and the
      # boot-time menu would race it.
      networking.firewall.extraInputRules = ''
        iifname "enp191s0" ip saddr 10.42.0.1 tcp dport { 4784, 5901 } accept
      '';
      # chrome-stream (pkgs/chrome-stream, 2026-09-13) is the other way to reach a
      # browser on this host: headless Chrome's CDP screencast, viewer and CDP both
      # on loopback, carried to the client by `ssh -L`. It rides this module so it
      # exists exactly where the shared browser desktop does, the strix.
      environment.systemPackages = [
        pkgs.browser-desktop
        pkgs.chrome-stream
        pkgs.keyring-unlock
      ];
      systemd.user.services.browser-desktop = {
        description = "Shared browser desktop (Sway and WayVNC)";
        # Keep open browser windows through configuration updates. Compositor
        # changes take effect at reboot or an explicit service restart.
        restartIfChanged = false;
        serviceConfig = {
          ExecStart = "${pkgs.browser-desktop}/bin/browser-desktop";
          Environment = [ "BROWSER_DESKTOP_VNC_ADDRESS=0.0.0.0" ];
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
          # Also clean up after SIGKILL or a compositor crash, when its shell
          # trap cannot run. Never leave a stale display for portal activation.
          ExecStopPost = "${pkgs.coreutils}/bin/rm -f %t/browser-desktop/environment %t/browser-desktop/portal-environment %t/browser-desktop/portal-environment.tmp";
        };
        unitConfig = {
          ConditionUser = "tom";
          StartLimitIntervalSec = 0;
        };
      };
      # On a physical seat the physical Sway session owns
      # the normal user portals. These headless-only
      # overrides must never bind them to the optional Sway service.
      # D-Bus activates portals through the user manager, which intentionally
      # has no global display on this headless host. Pass only these services
      # the current Sway display; stop them when that display goes away.
      # A headless caller must not start a compositor merely by probing portals.
      systemd.user.services.xdg-desktop-portal = lib.mkIf (!config.myDisplay.enable) {
        after = [ "browser-desktop.service" ];
        partOf = [ "browser-desktop.service" ];
        unitConfig.ConditionPathExists = "%t/browser-desktop/portal-environment";
        serviceConfig.EnvironmentFile = "%t/browser-desktop/portal-environment";
      };
      systemd.user.services.xdg-desktop-portal-gtk = lib.mkIf (!config.myDisplay.enable) {
        after = [ "browser-desktop.service" ];
        partOf = [ "browser-desktop.service" ];
        unitConfig.ConditionPathExists = "%t/browser-desktop/portal-environment";
        serviceConfig.EnvironmentFile = "%t/browser-desktop/portal-environment";
      };
      systemd.user.services.browser-desktop-menu = {
        description = "Chrome profile menu for the shared noVNC desktop";
        wantedBy = [ "default.target" ];
        after = [ "browser-desktop.service" ];
        serviceConfig = {
          ExecStart = "${pkgs.browser-desktop}/bin/browser-desktop-menu --host 0.0.0.0";
          Restart = "on-failure";
          RestartSec = 3;
          TimeoutStopSec = 15;
          UMask = "0077";
        };
        unitConfig.ConditionUser = "tom";
      };
    })
    (lib.mkIf cfg.frontDoor.enable {
      # The NAS fronts browser.internal. Only the noVNC viewer derivation is
      # referenced, so no Sway, WayVNC or Chrome enters this host's closure.
      services.caddy.enable = true;
      services.caddy.virtualHosts."http://browser.internal".extraConfig = ''
        redir https://browser.internal{uri} 308
      '';
      services.caddy.virtualHosts."https://browser.internal".extraConfig = ''
        tls internal
        handle /vnc {
          reverse_proxy ${cfg.frontDoor.backend}:5901
        }
        handle_path /desktop/* {
          reverse_proxy ${cfg.frontDoor.backend}:4784
        }
        handle_path /novnc/* {
          root * ${pkgs.browser-desktop.webRoot}
          file_server
        }
        handle {
          redir * /novnc/vnc.html?autoconnect=1&path=/vnc&resize=scale&reconnect=1&reconnect_delay=2000 302
        }
      '';
    })
  ];
}
