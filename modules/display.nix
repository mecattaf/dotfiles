{ lib, ... }:
# A physical seat gets Niri, greetd and Piri. Herdr/Tally remain independent
# of graphical-session.target. Coordinator and client are seats; worker and
# NAS are not. The optional headless browser desktop is a separate capability.
{
  options.myDisplay.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether this host runs a physical Niri desktop and greeter.";
  };
}
