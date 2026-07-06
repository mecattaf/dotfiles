{
  config,
  lib,
  pkgs,
  ...
}:
# home-manager.
#
# The RAW out-of-store symlinks below point at a *cloned checkout* of this repo at
# `repoDir`, enabling hot-reload without a rebuild. A fresh machine must clone the
# repo there BEFORE the first `home-manager switch`, else the symlinks dangle.
let
  repoDir = "${config.home.homeDirectory}/mecattaf/dotfiles";
  dots = "${repoDir}/home";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dots}/${path}";

  # Whole-dir RAW config dirs, one per ~/.config/<name>.
  configDirs = [
    "niri"
    "kitty"
    "fish"
    "starship"
    "zathura"
    "yt-dlp"
    "kanshi"
    "qt6ct"
    "shpool"
  ];

  # Python interpreter backing the niri helper bin/ scripts (wifi-menu, fzf-nmcli, …).
  pythonForNiri = pkgs.python3.withPackages (
    ps: with ps; [
      pycairo
      pygobject3
      pillow
      psutil
      pywayland
      requests
      setproctitle
      watchdog
      numpy
      ijson
    ]
  );

  # Chrome PWAs via google-chrome-stable --app. pwaIcon lets the entry name differ
  # from the icon filename (chatgpt→openai, claude→anthropic, gcloud→drive,
  # photos→images) so it references an icon that exists in dot_local/share/icons/.
  chrome = "${pkgs.google-chrome}/bin/google-chrome-stable";
  pwaIcon = name: icon: url: {
    inherit name;
    exec = "${chrome} --profile-directory=Default --app=${url}";
    icon = "${dots}/dot_local/share/icons/${icon}.png";
    categories = [ "Network" ];
  };
  pwa = name: pwaIcon name name;
in
{
  imports = [
    ./nvim.nix
    ./remote.nix
  ];

  home.username = "tom";
  home.homeDirectory = "/home/tom";
  programs.home-manager.enable = true;

  # Every home.packages tool must be on the SESSION PATH so niri spawns and
  # kitty-daemon `kitty @ launch` children find Nix-provided binaries.
  home.sessionPath = [ "$HOME/.nix-profile/bin" ];

  # Claude Code reads its config/creds from $CLAUDE_CONFIG_DIR (defaults to ~/.claude).
  # modules/secrets.nix seeds the OAuth credential to ~/.claude-main, so point Claude
  # Code there — otherwise the seeded cred lands where nothing reads it and Claude Code
  # re-prompts for OAuth on a fresh box despite the secret being delivered.
  home.sessionVariables.CLAUDE_CONFIG_DIR = "${config.home.homeDirectory}/.claude-main";

  # ---------------------------------------------------------------------------
  # RAW configs (whole-dir per ~/.config/<name>).
  # ---------------------------------------------------------------------------
  xdg.configFile =
    lib.genAttrs configDirs (d: {
      source = link "dot_config/${d}";
    })
    // {
      # kitty/ is a whole-dir out-of-store symlink, so the store-path fragment can't
      # nest inside it — emit at a neutral path; kitty.conf includes it by absolute
      # (env-expanded) path.
      "kitty-scrollback-nix.conf".text = ''
        # GENERATED — Nix-store path for kitty-scrollback.nvim kittens (offline-safe).
        action_alias kitty_scrollback_nvim kitten ${pkgs.vimPlugins.kitty-scrollback-nvim}/python/kitty_scrollback_nvim.py
      '';
    }
    // (
      # GTK4 / libadwaita apps (Nautilus) ignore gtk-theme-name; the only override
      # they honor is user CSS at ~/.config/gtk-4.0/. Link MacTahoe's gtk-4.0 assets
      # there so Nautilus renders the theme from first boot — home-manager's gtk
      # module does not do this, which is why nwg-look was needed before.
      let
        theme4 = "${pkgs.mactahoe-gtk-theme}/share/themes/MacTahoe-Dark-grey/gtk-4.0";
      in
      {
        "gtk-4.0/gtk.css".source = "${theme4}/gtk.css";
        "gtk-4.0/gtk-dark.css".source = "${theme4}/gtk-dark.css";
        "gtk-4.0/assets".source = "${theme4}/assets";
      }
    );

  # Belt-and-suspenders for any gsettings-aware app (agrees with GTK_THEME env).
  dconf.settings."org/gnome/desktop/interface" = {
    gtk-theme = "MacTahoe-Dark-grey";
    color-scheme = "prefer-dark";
    # Interface fonts, mirroring the Fedora box exactly (Nautilus, Remmina and
    # every other GTK app read font-name). sf-pro ships system-wide via
    # modules/common.nix fonts.packages; before this nothing set the key, so
    # GTK fell back to Adwaita Sans — the "odd Nautilus font" on first boot.
    font-name = "SF Pro Display 11";
    document-font-name = "Adwaita Sans 12";
    monospace-font-name = "Adwaita Mono 11";
  };

  # bin/ scripts: whole-dir (the repo owns ~/.local/bin).
  home.file.".local/bin".source = link "dot_local/bin";

  # icons for the PWA launchers (referenced by absolute path above).
  home.file.".local/share/icons/_repo".source = link "dot_local/share/icons";

  # wallpapers — whole-dir at ~/.local/share/wallpapers (wallpaper.jpg + placeholder).
  home.file.".local/share/wallpapers".source = link "dot_local/share/wallpapers";

  # bash login files. dot_bashrc sources ~/.env (secrets) — harmless missing-file
  # warning until that file exists.
  home.file.".bashrc".source = link "dot_bashrc";
  home.file.".bash_profile".source = link "dot_bash_profile";

  # Claude Code skills + settings (CLAUDE_CONFIG_DIR = ~/.claude-main, set above).
  # Deployed as individual out-of-store symlinks — NOT a whole-dir link — so
  # ~/.claude-main stays a real, writable directory that modules/secrets.nix can seed
  # .credentials.json into (a whole-dir symlink would push the credential into the
  # PUBLIC repo tree). Without this, a fresh box has zero skills/settings.
  home.file.".claude-main/skills".source = link "dot_claude/skills";
  home.file.".claude-main/settings.json".source = link "dot_claude/settings.json";

  # ---------------------------------------------------------------------------
  # PWA launchers (TYPED via xdg.desktopEntries; google-chrome, not flatpak).
  # ---------------------------------------------------------------------------
  xdg.desktopEntries = {
    chatgpt = pwaIcon "chatgpt" "openai" "https://chat.openai.com/";
    claude = pwaIcon "claude" "anthropic" "https://claude.ai/";
    gcloud = pwaIcon "gcloud" "drive" "https://drive.google.com/drive/u/0/";
    github = pwa "github" "https://github.com/mecattaf";
    "open-webui" = pwa "open-webui" "http://localhost:8080/";
    perplexity = pwa "perplexity" "https://perplexity.ai/";
    photos = pwaIcon "photos" "images" "https://photos.google.com/";
    railway = pwa "railway" "https://railway.app/dashboard";
    soundcloud = pwa "soundcloud" "https://soundcloud.com";
    whatsapp = pwa "whatsapp" "https://web.whatsapp.com/";
    "youtube-music" = pwa "youtube-music" "https://music.youtube.com";
  };

  # ---------------------------------------------------------------------------
  # git — the one typed config.
  # ---------------------------------------------------------------------------
  programs.git = {
    enable = true;
    lfs.enable = true; # restores the [filter "lfs"] block + puts git-lfs on PATH

    settings = {
      user.name = "mecattaf";
      user.email = "thomas@mecattaf.dev";
      init.defaultBranch = "main";
      credential.helper = "${pkgs.gh}/bin/gh auth git-credential";
    };
  };

  # ---------------------------------------------------------------------------
  # shpool — socket-activated session daemon. The nix package ships only the
  # binary, so the daemon/socket units are declared here.
  # ---------------------------------------------------------------------------
  systemd.user.services.shpool = {
    Unit = {
      Description = "Shpool - Shell Session Pool";
      Requires = [ "shpool.socket" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.shpool}/bin/shpool daemon";
      KillMode = "mixed";
      TimeoutStopSec = "2s";
      SendSIGHUP = "yes";
    };
    Install.WantedBy = [ "default.target" ];
  };
  systemd.user.sockets.shpool = {
    Unit.Description = "Shpool Shell Session Pooler";
    Socket = {
      ListenStream = "%t/shpool/shpool.socket";
      SocketMode = "0600";
    };
    Install.WantedBy = [ "sockets.target" ];
  };

  # ---------------------------------------------------------------------------
  # gtk/icon/cursor theming — mactahoe (overlay). GTK dirs are
  # MacTahoe-<Color>[-solid]-grey[-(x)hdpi]; icon dirs MacTahoe[-light|-dark].
  # ---------------------------------------------------------------------------
  gtk = {
    enable = true;
    theme = {
      name = "MacTahoe-Dark-grey";
      package = pkgs.mactahoe-gtk-theme;
    };
    iconTheme = {
      name = "MacTahoe-dark";
      package = pkgs.mactahoe-icon-theme;
    };
    cursorTheme = {
      name = "Bibata-Modern-Classic";
      package = pkgs.bibata-cursors;
    };
  };

  # ---------------------------------------------------------------------------
  # OBS Studio — the module wraps OBS so the plugin loads. obs-vkcapture is also
  # in home.packages so its Vulkan/GL capture layer + `obs-gamecapture` helper
  # land on the user profile for capturing other Wayland apps, not just OBS.
  # ---------------------------------------------------------------------------
  programs.obs-studio = {
    enable = true;
    plugins = with pkgs.obs-studio-plugins; [
      obs-vkcapture
    ];
  };

  # ---------------------------------------------------------------------------
  # user packages.
  # ---------------------------------------------------------------------------
  home.packages = with pkgs; [
    # browser
    google-chrome

    # fish init + shell
    eza
    zoxide
    atuin
    starship
    fzf
    bat
    ripgrep
    fd
    jq
    yq-go
    glow

    # niri / wayland desktop tooling. xwayland-satellite: niri's X11 path — X11 apps
    # and Chrome fallbacks need it on the session PATH.
    xwayland-satellite
    acpi
    brightnessctl
    playerctl
    swaybg
    wl-clipboard
    cliphist
    wl-gammarelay-rs
    kanshi
    grim
    slurp
    wf-recorder
    wl-mirror
    wmctrl
    wtype
    lisgd
    ddcutil
    cava
    pamixer
    pavucontrol
    nwg-look

    # the python interpreter the niri helper scripts need
    pythonForNiri

    # media / viewers
    yt-dlp
    aria2
    mpv
    imv
    vlc
    zathura
    ffmpeg-full
    ffmpegthumbnailer

    # screen/game recording — exposes the vkcapture host layer + obs-gamecapture on PATH.
    obs-studio-plugins.obs-vkcapture

    # files / nautilus + open-any-terminal + archive GUI
    nautilus
    nautilus-open-any-terminal
    xdg-terminal-exec
    xarchiver

    # session persistence + terminal
    shpool
    kitty

    # agent / dev tooling. claude-code from nixpkgs — the Fedora-era native installer
    # (~/.local/bin ELF) doesn't exist on NixOS; creds seed via modules/secrets.nix.
    claude-code
    gh
    google-cloud-sdk
    cloudflared
    backlog-md # bespoke pkg via overlay — see pkgs/backlog-md.nix

    # cursors (theme dep)
    bibata-cursors

    # codecs/gstreamer plugins for thumbnailers + portals
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    libjxl
  ];

  # nvim → implemented in ./nvim.nix (imported above).

  home.stateVersion = "26.05";
}
