{ lib, ... }:
# A physical seat gets Sway (modules/sway.nix) and greetd. Herdr remains
# independent of graphical-session.target. The client is a seat; the strix
# and the NAS are not. The optional headless browser desktop is a separate
# capability. modules/common.nix derives programs.swayPhysical and greetd
# from this option. niri and scroll are retired (Tom, settled 2026-10-13).
{
  options.myDisplay = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether this host runs a physical desktop and greeter.";
    };
  };
}
