{ inputs, ... }:
# Domicile under trial on the client, beside Sway. Sway stays the base config
# and the boot default; nothing here starts Domicile on an ordinary boot. This
# adds both of upstream's modules and leaves greetd as modules/common.nix has it.
#
# Do not copy upstream's services.displayManager or gdm lines. greetd runs a
# command and reads no .desktop file, and gdm would be a second greeter.
{
  imports = [ inputs.domicile.nixosModules.default ];

  programs.domicile = {
    enable = true;
    # The default opens TCP 7236 on every interface. This host serves nothing.
    miracast = false;
  };

  # The group carries upstream's nice and rtprio limits, from the next login.
  users.users.tom.extraGroups = [ "domicile" ];

  home-manager.users.tom = {
    imports = [ inputs.domicile.homeManagerModules.default ];

    programs.domicile = {
      enable = true;
      # The key table. Its built Shell becomes the shell, so set neither `shell`
      # nor `settings.shell` beside it.
      configDirectory = ../home/domicile;
      # Leave settings.idle.lock_after_seconds unset. Blanking does not lock
      # without it.
    };
  };
}
