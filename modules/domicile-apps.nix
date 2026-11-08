{ pkgs, lib, ... }:
# Import beside modules/domicile.nix. No session, server unit or key ownership.
# home/home.nix already installs every file in dot_local/bin.
{
  home-manager.users.tom = { lib, ... }: {
    # Reuse home/home.nix's Python environment and common.nix's fish. A second
    # bare Python would collide with the existing Python-with-packages profile.
    home.packages = [
      pkgs.google-chrome
      pkgs.libnotify
      pkgs.nautilus
      pkgs.kitty
    ];
    home.sessionVariables.BROWSER = "/home/tom/.local/bin/desktop-web";
    home.activation.desktopRouting = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if [ -n "''${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ]; then
        run ${pkgs.python3}/bin/python3 /home/tom/.local/bin/desktop-routing-live
      fi
    '';
    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "x-scheme-handler/http" = [ "google-chrome.desktop" ];
        "x-scheme-handler/https" = [ "google-chrome.desktop" ];
        "x-scheme-handler/about" = [ "google-chrome.desktop" ];
        "x-scheme-handler/unknown" = [ "google-chrome.desktop" ];
        "x-scheme-handler/claude-cli" = [ "claude-code-url-handler.desktop" ];
        "text/html" = [ "google-chrome.desktop" ];
        "application/pdf" = [ "google-chrome.desktop" ];
        "inode/directory" = [ "org.gnome.Nautilus.desktop" ];
        "text/plain" = [ "kitty-nvim.desktop" ];
        "text/markdown" = [ "kitty-nvim.desktop" ];
        "text/x-markdown" = [ "kitty-nvim.desktop" ];
      }
      // lib.genAttrs [
        "image/png"
        "image/jpeg"
        "image/gif"
        "image/webp"
        "image/avif"
        "image/bmp"
        "image/tiff"
        "image/svg+xml"
        "image/heif"
        "image/heic"
        "image/jxl"
        "image/x-icon"
        "image/vnd.microsoft.icon"
        "image/x-xbitmap"
        "image/x-portable-anymap"
        "image/x-portable-bitmap"
        "image/x-portable-graymap"
        "image/x-portable-pixmap"
        "image/x-qoi"
        "image/*"
      ] (_: [ "imv.desktop" ])
      // lib.genAttrs [
        "video/mp4"
        "video/webm"
        "video/x-matroska"
        "video/quicktime"
        "video/mpeg"
        "video/ogg"
        "video/x-msvideo"
        "video/x-flv"
        "video/mp2t"
        "video/3gpp"
        "video/3gpp2"
        "video/x-ms-wmv"
        "video/*"
      ] (_: [ "mpv.desktop" ]);
    };
    xdg.configFile."herdr/desktop-client.toml".text =
      builtins.replaceStrings [ "[ui]\n" ] [ "[ui]\nprompt_new_workspace_name = true\n" ]
        (builtins.readFile ../home/dot_config/herdr/config.toml);
    # Finder enumerates these actions through Domicile's native app index.
    xdg.desktopEntries = {
      rog-control-center = {
        name = "ROG Control Center";
        noDisplay = true;
      };
      audio-speaker = {
        name = "Audio: dock speakers and webcam microphone";
        exec = "audio-route speaker";
        icon = "audio-speakers";
        terminal = false;
      };
      audio-inzone = {
        name = "Audio: INZONE Buds and microphone";
        exec = "audio-route inzone";
        icon = "audio-headphones";
        terminal = false;
      };
      audio-internal = {
        name = "Audio: laptop speakers and microphone";
        exec = "audio-route internal";
        icon = "audio-speakers";
        terminal = false;
      };
      inzone-noise-cancelling = {
        name = "INZONE: noise cancelling";
        exec = "zoneout --device buds --set nc_mode 1";
        icon = "audio-headphones";
        terminal = false;
      };
      inzone-ambient = {
        name = "INZONE: ambient sound";
        exec = "zoneout --device buds --set nc_mode 2";
        icon = "audio-headphones";
        terminal = false;
      };
      inzone-noise-off = {
        name = "INZONE: noise control off";
        exec = "zoneout --device buds --set nc_mode 0";
        icon = "audio-headphones";
        terminal = false;
      };
      inzone-balance = {
        name = "INZONE: center game and chat balance";
        exec = "zoneout --device buds --set balance 50";
        icon = "audio-headphones";
        terminal = false;
      };
      kitty-nvim = {
        name = "Neovim in Kitty";
        comment = "Edit text and Markdown in a local Kitty terminal";
        exec = "kitty --class kitty-nvim -e nvim -- %F";
        icon = "nvim";
        categories = [
          "Utility"
          "TextEditor"
        ];
        mimeType = [
          "text/plain"
          "text/markdown"
          "text/x-markdown"
        ];
        terminal = false;
      };
      domicile-terminal = {
        name = "NAS terminal";
        comment = "Fresh NAS shell in Kitty over SSH";
        exec = "domicile-apps terminal";
        icon = "utilities-terminal";
        categories = [
          "System"
          "TerminalEmulator"
        ];
        terminal = false;
      };
      domicile-rescue = {
        name = "Local terminal";
        exec = "domicile-apps rescue";
        icon = "utilities-terminal";
        categories = [
          "System"
          "TerminalEmulator"
        ];
        terminal = false;
      };
      domicile-chrome = {
        name = "Google Chrome (Domicile)";
        exec = "domicile-apps chrome %U";
        icon = "google-chrome";
        categories = [
          "Network"
          "WebBrowser"
        ];
        terminal = false;
      };
      domicile-files = {
        name = "Files (Domicile)";
        exec = "domicile-apps files %U";
        icon = "org.gnome.Nautilus";
        categories = [
          "System"
          "FileManager"
        ];
        terminal = false;
      };
    };
  };
}
