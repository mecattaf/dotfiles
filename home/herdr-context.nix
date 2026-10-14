{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  cfg = config.services.herdrContext;
in
{
  options.services.herdrContext = {
    enable = lib.mkEnableOption "Herdr workspace views and desktop attention" // {
      default = osConfig.myDisplay.enable;
    };
    webUrl = lib.mkOption {
      type = lib.types.str;
      # Measured on Strix, 2026-10-14: Tailscale Serve routes this HTTPS
      # endpoint to the installed web UI on 127.0.0.1:7318. The physical
      # client must not use localhost, which would address the laptop.
      default = "https://strix.tail8dd1.ts.net:8443/";
      description = "Herdr web UI URL reachable from the physical Sway seat.";
    };
  };

  config = lib.mkIf (cfg.enable && osConfig.myDisplay.enable) {
    # Keep the helpers in the existing raw bin directory. rawDotfiles.link
    # copies it into the store on the client and links the checkout on Strix.
    # Neither this module nor its activation touches the Herdr server.
    xdg.configFile."herdr/context.json".text = builtins.toJSON {
      web_url = cfg.webUrl;
    };

    systemd.user.services.herdr-attention = {
      Unit = {
        Description = "Herdr workspace attention for the physical Sway desktop";
        # The session imports SWAYSOCK before it starts this target. Never
        # attach to a headless browser compositor or a stale socket at login.
        ConditionEnvironment = "SWAYSOCK";
        After = [ "sway-physical-session.target" ];
        PartOf = [ "sway-physical-session.target" ];
      };
      Service = {
        ExecStart = "%h/.local/bin/herdr-attention";
        Restart = "on-failure";
        RestartSec = 5;
        Environment = [
          "PATH=${
            lib.makeBinPath [
              pkgs.python3
              pkgs.sway
              pkgs.openssh
              pkgs.libnotify
              pkgs.google-chrome
              pkgs.kitty
            ]
          }:%h/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin"
          "HERDR_SWAY_LOCAL=${if osConfig.networking.hostName == "strix" then "1" else "0"}"
        ];
      };
      Install.WantedBy = [ "sway-physical-session.target" ];
    };

    xdg.desktopEntries.herdr-context-toggle = {
      name = "Switch Herdr Terminal / Chat";
      genericName = "Change the view of the current Herdr workspace";
      exec = "${config.home.homeDirectory}/.local/bin/herdr-context toggle";
      terminal = false;
      categories = [ "Utility" ];
      icon = "utilities-terminal";
    };
  };
}
