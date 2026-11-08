{ pkgs, ... }:
# Import beside modules/domicile.nix. No session, server unit or key ownership.
# home/home.nix already installs every file in dot_local/bin.
{
  home-manager.users.tom = {
    # Reuse home/home.nix's Python environment and common.nix's fish. A second
    # bare Python would collide with the existing Python-with-packages profile.
    home.packages = [ pkgs.google-chrome pkgs.nautilus pkgs.kitty ];
    xdg.configFile."herdr/desktop-client.toml".text = builtins.replaceStrings
      [ "[ui]\n" ] [ "[ui]\nprompt_new_workspace_name = true\n" ]
      (builtins.readFile ../home/dot_config/herdr/config.toml);
    xdg.desktopEntries = {
      domicile-terminal = {
        name = "NAS terminal";
        comment = "Fresh NAS shell in Kitty over SSH";
        exec = "domicile-apps terminal";
        icon = "utilities-terminal";
        categories = [ "System" "TerminalEmulator" ];
        terminal = false;
      };
      domicile-rescue = {
        name = "Local terminal";
        exec = "domicile-apps rescue";
        icon = "utilities-terminal";
        categories = [ "System" "TerminalEmulator" ];
        terminal = false;
      };
      domicile-chrome = {
        name = "Google Chrome (Domicile)";
        exec = "domicile-apps chrome %U";
        icon = "google-chrome";
        categories = [ "Network" "WebBrowser" ];
        terminal = false;
      };
      domicile-files = {
        name = "Files (Domicile)";
        exec = "domicile-apps files %U";
        icon = "org.gnome.Nautilus";
        categories = [ "System" "FileManager" ];
        terminal = false;
      };
    };
  };
}
