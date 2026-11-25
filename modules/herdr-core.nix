{
  config,
  lib,
  pkgs,
  ...
}:
# The hc core's host half, on the brain only (the user half, hc-core.service
# and config.toml, is home/herdr-core.nix; runbook docs/herdr-core.md).
#
# kitty's terminfo system-wide, so `xterm-kitty` resolves from
# /run/current-system/sw/share/terminfo (on TERMINFO_DIRS) for every hc
# terminal: Mod+Enter stations get TERM=xterm-kitty from hc-station when it
# resolves, and Kitty's identity is what makes Claude Code push Kitty keyboard
# flags and report OSC 7501 on its own. Until now the NAS resolved it only from
# ~/.terminfo, left there by `kitten ssh`, which a core started by a unit and
# its terminals must not depend on. Only the terminfo output is installed, not
# kitty itself: the NAS has no display.
{
  config = lib.mkIf (config.myFleet.has "brain") {
    environment.systemPackages = [ pkgs.kitty.terminfo ];
  };
}
