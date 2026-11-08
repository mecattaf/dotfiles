# Public composition only: the owned Domicile module checks and bundles this
# rendered entry with its unchanged Imagine production dependency.
{ config, lib, pkgs, ... }:
let
  home = config.home-manager.users.tom;
  package = home.programs.agencyKitty.package;
  template = builtins.readFile ../home/dot_config/domicile/domicile.tsx;
  entry = pkgs.writeText "agency-domicile-entry.tsx" (
    builtins.replaceStrings [ "@AGENCY_KITTY_COMMAND@" ]
      [ "${package}/bin/agency-kitty" ] template
  );
in {
  assertions = [
    { assertion = lib.hasInfix "@AGENCY_KITTY_COMMAND@" template;
      message = "Render the reviewed native catalogue entry through the selected seat helper."; }
    { assertion = home.programs.agencyKitty.enable && home.programs.agencyEditor.viAlias;
      message = "The composed desktop requires the primary native local Neovim UI."; }
    { assertion = pkgs.kitty.version == "0.50.0";
      message = "The composed desktop requires the qualified native Kitty version."; }
  ];
  programs.domicilePhysical.configSource = entry;
}
