{ lib, ... }:
# Physical desktop only. Headless browser-desktop remains independently on Sway.
{
  options.myDisplay = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether this host runs a physical desktop and greeter.";
    };
    session = lib.mkOption {
      type = lib.types.enum [ "sway" "hyprland" ];
      default = "sway";
      description = "Compositor selected for the next physical login; Sway remains a recovery session.";
    };
  };
}
