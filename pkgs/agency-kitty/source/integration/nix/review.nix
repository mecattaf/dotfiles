# Evaluate/build on strix-coordinator after staging this repo + dotfiles there.
# This expression never activates a profile, edits a key table or restarts a unit.
{ dotfiles, latestKitty ? false, target ? "client" }:
let
  flake = builtins.getFlake "path:${toString dotfiles}";
  base = flake.nixosConfigurations.${target};
  pkgs = base.pkgs;
  kittyPackage = if latestKitty && pkgs.kitty.version != "0.50.0"
    then import (dotfiles + "/pkgs/kitty-0.50.nix") { inherit pkgs; }
    else pkgs.kitty;
  holderPackage = pkgs.callPackage ../../backend/zmx/source-build.nix { };
  package = pkgs.callPackage ../../default.nix { inherit holderPackage; kitty = kittyPackage; };
  checked = base.extendModules {
    modules = [{
      home-manager.users.tom.programs.agencyKitty = { enable = true; inherit package kittyPackage; };
      home-manager.users.tom.programs.agencyEditor = { enable = true; viAlias = builtins.elem target [ "client" "nas" ]; };
    }];
  };
  home = checked.config.home-manager.users.tom;
in {
  inherit package holderPackage kittyPackage;
  admission = {
    target = target;
    failedAssertions = map (entry: entry.message) (builtins.filter (entry: !entry.assertion) home.assertions);
    kittyVersion = kittyPackage.version;
    persistentHolderVersion = holderPackage.version;
    managedKittyConfig = home.xdg.configFile."agency-kitty/kitty.conf".text or null;
    viAlias = home.programs.agencyEditor.viAlias;
    activates = false;
  };
}
