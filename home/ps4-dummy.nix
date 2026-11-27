{
  config,
  inputs,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  suite = osConfig.myPs4.fleetSuite.enable;
  system = pkgs.stdenv.hostPlatform.system;
in
{
  imports = [
    ./raw-dotfiles-guard.nix
    ./herdr-core.nix
    ./ssh.nix
  ];

  home.username = "tom";
  home.homeDirectory = "/home/tom";
  home.stateVersion = "26.05";
  rawDotfiles.inStore = true;
  programs.home-manager.enable = true;
  programs.herdrCore = {
    enable = suite;
    autoStart = false;
  };
  programs.git.enable = true;
  programs.bash.enable = true;
  home.sessionVariables.EDITOR = "nvim";
  home.sessionPath = [ "$HOME/.local/bin" ];
  home.file.".local/bin/runtime-test".source =
    config.lib.rawDotfiles.link "dot_local/bin/runtime-test";
  home.packages =
    with pkgs;
    [
      neovim
      ripgrep
      rsync
      bubblewrap
      coreutils
      kitty.terminfo
    ]
    ++ lib.optionals suite [
      kitty
      fish
      anthropic-mono-nerd
      inputs.domicile.packages.${system}.manganese
    ];

  # No compositor, browser engine or terminal core starts at boot. The same
  # fleet herdr-core package is installed above; the optional suite supplies
  # a clean, manually started hc-core.service. The optional suite consumes disk until used.
  xdg.configFile = lib.mkIf suite {
    "kitty".source = config.lib.rawDotfiles.link "dot_config/kitty";
    "kitty-scrollback-nix.conf".text = ''
      action_alias kitty_scrollback_nvim kitten ${pkgs.vimPlugins.kitty-scrollback-nvim}/python/kitty_scrollback_nvim.py
    '';
    # The fleet Kitty file includes this path. Keep the selected Noir colors
    # available without starting the client desktop's theme/service machinery.
    "theme/kitty.conf".text = (import ./themes { inherit lib; }).fragments."themes/noir/kitty.conf";
  };
}
