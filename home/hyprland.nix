{ config, lib, pkgs, osConfig, ... }:
let
  enabled = osConfig.myDisplay.enable && osConfig.myDisplay.session == "hyprland";
  target = "hyprland-physical-session.target";
in {
  config = lib.mkIf enabled {
    xdg.configFile."hypr".source = config.lib.rawDotfiles.link "dot_config/hypr";
    xdg.configFile."hyprland-local.conf".text = lib.optionalString (osConfig.networking.hostName == "client") ''
      # Zenbook Duo: 2880x1800 panels at 2x, eDP-2 below eDP-1.
      monitor = eDP-1, preferred, 0x0, 2
      monitor = eDP-2, preferred, 0x900, 2
      input:touchdevice:output = eDP-1
      bindl = , switch:on:Lid Switch, exec, hyprctl keyword monitor "eDP-1,disable"
      bindl = , switch:off:Lid Switch, exec, hyprctl keyword monitor "eDP-1,preferred,0x0,2"
      bind = , F10, exec, ~/.local/bin/brightness toggle
      bindl = , XF86MonBrightnessDown, exec, ~/.local/bin/brightness down
      bindl = , XF86MonBrightnessUp, exec, ~/.local/bin/brightness up
      bindl = SHIFT, XF86MonBrightnessDown, exec, ~/.local/bin/brightness down 2%
      bindl = SHIFT, XF86MonBrightnessUp, exec, ~/.local/bin/brightness up 2%
      bindl = , XF86AudioMicMute, exec, ~/.local/bin/volume micmute
    '';
    home.packages = [ pkgs.desktop-shell ];
    systemd.user.services.desktop-shell = {
      Unit = {
        Description = "Solid desktop work and navigation surface";
        After = [ target ];
        PartOf = [ target ];
        ConditionEnvironment = "HYPRLAND_INSTANCE_SIGNATURE";
      };
      Service = {
        ExecStart = "${pkgs.desktop-shell}/bin/desktop-shell bar";
        Restart = "on-failure";
        RestartSec = 2;
        Slice = "app.slice";
      };
      Install.WantedBy = [ target ];
    };
  };
}
