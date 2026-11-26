{
  inputs,
  osConfig,
  ...
}:
# The factory floor (`agency`, github.com/agency-agency/factory-floor): a
# Cordis orchestrator on herdr-core. The unit, its launcher and every option
# come from the floor flake's Home Manager module (nix/module.nix there). It
# renders the unit this file declared until 2026-11-26: the same environment,
# UnsetEnvironment list, exit 78, keep-old, and in checkout mode the same
# launcher store path. This host runs the flake's package from the store and
# gets `agency` on PATH; `package = null` returns to the local checkout
# (~/mecattaf/factory-floor, installed by hand).
#
# NOT AUTOSTARTED, NO WAKE: unchanged. autostart and heartbeatWake stay off,
# and docs/factory-floor.md has both flips. home/scheduled.nix still reads
# services.factory-floor.floorUnit.
{
  imports = [ inputs.factory-floor.homeManagerModules.default ];

  services.factory-floor = {
    enable = osConfig.myFleet.has "brain";
    documentation = [ "https://github.com/mecattaf/dotfiles/blob/main/docs/factory-floor.md" ];
  };
}
