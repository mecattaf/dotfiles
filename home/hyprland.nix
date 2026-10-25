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
      # Names read from the client sysfs input inventory on 2026-10-14;
      # Hyprland 0.56 lowercases and replaces spaces with hyphens.
      # Preserve Sway: adaptive touchpads, flat ordinary pointers.
      device {
        name = apple-inc.-magic-trackpad
        accel_profile = adaptive
      }
      device {
        name = elan9008:00-04f3:425b-touchpad
        accel_profile = adaptive
      }
      device {
        name = elan9009:00-04f3:425a-touchpad
        accel_profile = adaptive
      }
      bindl = , switch:on:Lid Switch, exec, hyprctl keyword monitor "eDP-1,disable"
      bindl = , switch:off:Lid Switch, exec, hyprctl keyword monitor "eDP-1,preferred,0x0,2"
      bind = , F10, exec, ~/.local/bin/brightness toggle
      bindl = , XF86MonBrightnessDown, exec, ~/.local/bin/brightness down
      bindl = , XF86MonBrightnessUp, exec, ~/.local/bin/brightness up
      bindl = SHIFT, XF86MonBrightnessDown, exec, ~/.local/bin/brightness down 2%
      bindl = SHIFT, XF86MonBrightnessUp, exec, ~/.local/bin/brightness up 2%
      bindl = , XF86AudioMicMute, exec, ~/.local/bin/volume micmute
    '';
    home.packages = [ pkgs.desktop-shell pkgs.cliphist pkgs.wl-clipboard ];
    systemd.user.services.desktop-shell-core = {
      Unit = {
        Description = "Desktop shell notification and control service";
        After = [ target ];
        PartOf = [ target ];
        ConditionEnvironment = "HYPRLAND_INSTANCE_SIGNATURE";
      };
      Service = {
        Type = "dbus";
        BusName = "org.freedesktop.Notifications";
        ExecStart = "${pkgs.desktop-shell}/bin/desktop-shell daemon";
        Restart = "on-failure";
        RestartSec = 2;
        Slice = "app.slice";
        UMask = "0077";
      };
      Install.WantedBy = [ target ];
    };
    systemd.user.services.desktop-shell-clipboard-text = {
      Unit = {
        Description = "Native shell text clipboard history";
        After = [ target ];
        PartOf = [ target ];
        ConditionEnvironment = "HYPRLAND_INSTANCE_SIGNATURE";
      };
      Service = {
        ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store";
        Restart = "on-failure";
        RestartSec = 2;
        UMask = "0077";
      };
      Install.WantedBy = [ target ];
    };
    systemd.user.services.desktop-shell-clipboard-image = {
      Unit = {
        Description = "Native shell image clipboard history";
        After = [ target ];
        PartOf = [ target ];
        ConditionEnvironment = "HYPRLAND_INSTANCE_SIGNATURE";
      };
      Service = {
        ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${pkgs.cliphist}/bin/cliphist store";
        Restart = "on-failure";
        RestartSec = 2;
        UMask = "0077";
      };
      Install.WantedBy = [ target ];
    };
    systemd.user.services.desktop-shell = {
      Unit = {
        Description = "Solid desktop work and navigation surface";
        After = [ target "desktop-shell-core.service" ];
        Requires = [ "desktop-shell-core.service" ];
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
