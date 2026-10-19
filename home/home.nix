{
  config,
  inputs,
  lib,
  pkgs,
  osConfig,
  ...
}:
# home-manager.
#
# The RAW out-of-store symlinks below point at a *cloned checkout* of this repo at
# `repoDir`, enabling hot-reload without a rebuild. A fresh machine must clone the
# repo there BEFORE the first `home-manager switch`, else the symlinks dangle.
# That checkout, not the flake switched from, supplies the raw half of every
# switch: ./raw-dotfiles-guard.nix fails the activation, before writeBoundary,
# when a user unit's %h/.local/bin/<program> is missing from it (#313), and
# AGENTS.md carries the ordering rule. Exception: a host with
# rawDotfiles.inStore (the client and the strix hosts) gets the same files from
# the Nix store and has no checkout (./raw-dotfiles-guard.nix).
let
  link = config.lib.rawDotfiles.link;

  hostName = osConfig.networking.hostName;
  isSeat = osConfig.myFleet.has "seat";
  isBrain = osConfig.myFleet.has "brain";

  # Upstream's minimal output also exposes libexec/git-core from its own Git.
  # Share only commands so the NAS's stable programs.git owns that tree.
  gitAiTools = pkgs.buildEnv {
    name = "git-ai-commands";
    paths = [ inputs.git-ai.packages.${pkgs.stdenv.hostPlatform.system}.minimal ];
    pathsToLink = [ "/bin" ];
  };

  # Whole-dir RAW config dirs, one per ~/.config/<name>.
  configDirs = [
    "fish"
    "starship"
    "yt-dlp"
  ]
  ++ lib.optionals isSeat [
    "sway"
    "kitty"
    "ghostty"
    "kanshi"
    "qt6ct"
  ];

  # Non-brain hosts keep raw hot reload per file while omitting the three agent-only
  # wrappers on seat/compute profiles (#552). An unfiltered whole-dir link
  # cannot express that boundary.
  binNames = lib.filter (
    name:
    isBrain
    || !(builtins.elem name [
      "mail"
      "crm"
      "project"
    ])
  ) (builtins.attrNames (builtins.readDir ./dot_local/bin));
  binDir = pkgs.linkFarm "dotfiles-bin" (
    map (name: {
      inherit name;
      path = link "dot_local/bin/${name}";
    }) binNames
  );

  # Python interpreter backing the helper bin/ scripts (wifi-menu, fzf-nmcli, …).
  pythonForScripts = pkgs.python3.withPackages (
    ps:
    with ps;
    [
      pillow
      psutil
      requests
      setproctitle
      watchdog
      numpy
      ijson
    ]
    ++ lib.optionals isSeat [
      pycairo
      pygobject3
      pywayland
    ]
    ++ lib.optionals isBrain [
      # CLI-Anything's generated harnesses and validation workflow assume these
      # are importable from the ordinary `python3`, not only inside cli-hub.
      click
      pytest
    ]
  );

in
{
  imports = [
    ./browser-trust.nix
    ./agent-tools.nix
    ./agent-helpers.nix
    ./ai-memory.nix
    ./dsh.nix
    ./downloads-mirror.nix
    ./harness-records.nix
    ./herdr.nix
    ./nvim.nix
    ./paper.nix
    ./utility-storage.nix
    ./raw-dotfiles-guard.nix
    ./ssh.nix
  ]
  ++ lib.optionals isSeat [
    ./client-apps.nix
    ./theme.nix
    ./vicinae.nix
  ];

  home.username = "tom";
  home.homeDirectory = "/home/tom";
  programs.home-manager.enable = true;

  # Every home.packages tool must be on the SESSION PATH so Sway's exec and
  # kitty-daemon `kitty @ launch` children find Nix-provided binaries.
  home.sessionPath = [
    "$HOME/.nix-profile/bin"
    "$HOME/.local/bin"
  ];

  # ---------------------------------------------------------------------------
  # RAW configs (whole-dir per ~/.config/<name>).
  # ---------------------------------------------------------------------------
  xdg.configFile =
    lib.genAttrs configDirs (d: {
      source = link "dot_config/${d}";
    })
    // lib.optionalAttrs isSeat {
      # kitty/ is a whole-dir out-of-store symlink, so the store-path fragment can't
      # nest inside it — emit at a neutral path; kitty.conf includes it by absolute
      # (env-expanded) path.
      "kitty-scrollback-nix.conf".text = ''
        # GENERATED — Nix-store path for kitty-scrollback.nvim kittens (offline-safe).
        action_alias kitty_scrollback_nvim kitten ${pkgs.vimPlugins.kitty-scrollback-nvim}/python/kitty_scrollback_nvim.py
      '';

      "sway-local.conf".text =
        lib.optionalString (osConfig.myFleet.has "compute") ''
          output DP-4 scale 2 position 0 0
          output DP-1 scale 2 position 2560 0
        ''
        + lib.optionalString (hostName == "client") ''
          # Zenbook Duo: logical 1440x900 panels, vertically stacked.
          output eDP-1 scale 2 position 0 0
          output eDP-2 scale 2 position 0 900
          # Per-panel touch and pen mapping, recovered from the Scroll config;
          # device identifiers confirmed on the client on 2026-10-19.
          input "1267:16987:ELAN9008:00_04F3:425B" map_to_output eDP-1
          input "1267:16986:ELAN9009:00_04F3:425A" map_to_output eDP-2
          input "1267:16987:ELAN9008:00_04F3:425B_Stylus" map_to_output eDP-1
          input "1267:16986:ELAN9009:00_04F3:425A_Stylus" map_to_output eDP-2
          bindswitch --reload --locked lid:on output eDP-1 disable
          bindswitch --reload --locked lid:off output eDP-1 enable
          bindsym --no-warn F10 exec ~/.local/bin/brightness toggle
          # Plain F-keys (external keyboard or Fn): brightness aliases.
          # Keep the theme/accent pickers available under Super instead.
          bindsym --locked F1 exec ~/.local/bin/brightness down
          bindsym --locked --no-warn F2 exec ~/.local/bin/brightness up
          bindsym --locked --no-warn Shift+F2 exec ~/.local/bin/brightness up 100%
          bindsym --no-repeat Mod4+F2 exec kitty --class theme-prompt -e ~/.local/bin/theme-prompt theme
          bindsym --no-repeat Mod4+Shift+F2 exec kitty --class theme-prompt -e ~/.local/bin/theme-prompt accent
          bindsym --locked XF86MonBrightnessDown exec ~/.local/bin/brightness down
          bindsym --locked XF86MonBrightnessUp exec ~/.local/bin/brightness up
          # Shift+F5/F6: 2% fine steps (Tom, 2026-10-10). The XF86 keysym comes
          # from the daemon's virtual keyboard while Shift is held on the
          # physical one; Sway's default keyboard_grouping=smart groups both
          # (same keymap and repeat info), so the modifier carries across.
          bindsym --locked Shift+XF86MonBrightnessDown exec ~/.local/bin/brightness down 2%
          bindsym --locked Shift+XF86MonBrightnessUp exec ~/.local/bin/brightness up 2%
          bindsym --locked XF86AudioMicMute exec ~/.local/bin/volume micmute
        '';

    };
  # (The gtk-4.0/{gtk.css,gtk-dark.css,assets} links that used to sit here — a
  # store symlink of MacTahoe-Dark-grey's gtk-4.0 — moved to home/theme.nix,
  # where they point through the ~/.config/theme pointer at whichever theme's
  # MacTahoe variant is selected. 2026-09-17.)

  # Standard desktop entries are searchable by Vicinae and its replacement.
  xdg.desktopEntries = lib.mkIf (hostName == "client") {
    brightness-down = {
      name = "Brightness down";
      comment = "Dim both laptop screens by 10%";
      exec = "${config.home.homeDirectory}/.local/bin/brightness down";
      icon = "display-brightness-symbolic";
      terminal = false;
      categories = [ "Settings" ];
      settings.Keywords = "brightness;screen;display;dim;";
    };
    brightness-up = {
      name = "Brightness up";
      comment = "Brighten both laptop screens by 10%";
      exec = "${config.home.homeDirectory}/.local/bin/brightness up";
      icon = "display-brightness-symbolic";
      terminal = false;
      categories = [ "Settings" ];
      settings.Keywords = "brightness;screen;display;brighten;";
    };
    brightness-max = {
      name = "Maximum brightness";
      comment = "Set both laptop screens to 100%";
      exec = "${config.home.homeDirectory}/.local/bin/brightness up 100";
      icon = "display-brightness-symbolic";
      terminal = false;
      categories = [ "Settings" ];
      settings.Keywords = "brightness;screen;display;maximum;100;";
    };
  };

  # gtk-theme / icon-theme / color-scheme are deliberately NOT pinned here any
  # more (2026-09-17): the theme switcher owns them at runtime (`theme apply`
  # → gsettings, docs/theme-switcher-2026-09-17.md), and a pinned value would
  # snap a light session back to Dark on every switch. dconf keeps whatever
  # `theme` last wrote. Fonts stay.
  dconf.settings."org/gnome/desktop/interface" = lib.mkIf isSeat {
    # Interface fonts for Nautilus and every other GTK app that reads
    # font-name. sf-pro ships system-wide via modules/common.nix fonts.packages
    # (the one Apple family kept in the 2026-08-21 sweep — "too good to
    # have"); before this key was set at all, GTK fell back to Adwaita Sans —
    # the "odd Nautilus font" on first boot.
    # 2026-09-17: the Anthropic suite. All three keys move together so the
    # desktop is consistent on day one; sizes preserved so no GTK app changes
    # metrics. sf-pro stays installed and reachable by name.
    # fc-match "Anthropic Sans" returns the file's default instance (opsz 16 =
    # the Text cut), the right optical size for an 11 pt UI.
    font-name = "Anthropic Sans 11";
    document-font-name = "Anthropic Serif 12";
    monospace-font-name = "AnthropicMono Nerd Font 11";
  };

  # bin/ scripts: whole-dir (the repo owns ~/.local/bin).
  home.file.".local/bin".source = if isBrain then link "dot_local/bin" else binDir;

  # icons for the PWA launchers (referenced by absolute path above).
  home.file.".local/share/icons/_repo" = lib.mkIf isSeat { source = link "dot_local/share/icons"; };

  # wallpapers — whole-dir at ~/.local/share/wallpapers (wallpaper.jpg + placeholder).
  home.file.".local/share/wallpapers" = lib.mkIf isSeat {
    source = link "dot_local/share/wallpapers";
  };

  # One stable $HOME path the docs can name for the Anthropic woff2 + CSS, since
  # the real one is the profile path /etc/profiles/per-user/tom/share/webfonts.
  # Measured safe 2026-09-17: fontconfig's only xdg directory is
  # `<dir prefix="xdg">fonts</dir>` (/etc/fonts/fonts.conf:104), i.e.
  # ~/.local/share/fonts EXACTLY — so a sibling named `webfonts` is not scanned.
  # DO NOT rename this to `fonts`.
  home.file.".local/share/webfonts" = lib.mkIf isSeat {
    source = "${pkgs.anthropic-webfonts}/share/webfonts";
  };

  # bash login files. dot_bashrc sources ~/.env (secrets) — harmless missing-file
  # warning until that file exists.
  home.file.".bashrc".source = link "dot_bashrc";
  home.file.".bash_profile".source = link "dot_bash_profile";

  # No Chrome --app launcher entries on any host (Tom, 2026-10-12: "i do not
  # want th e chrome shortcuts neither. this goes for cross-nixosfleet").

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
  # atuin — shell history for the seats, synced through the self-hosted server
  # on the NAS (modules/atuin.nix, imported by hosts/nas/agent-host.nix). The
  # package here replaces the old bare `atuin` entry in home.packages; fish's
  # own init call + the Ctrl+E rebind stay in dot_config/fish/config.fish
  # (enableFishIntegration = false avoids home-manager wiring a second one),
  # behind its `type -q atuin` gate.
  #
  # Not on the NAS home (T-55, 2026-10-25). Atuin is on its way out, so the
  # NAS home is the vanilla fish one: fish's own history, no atuin client,
  # no key seed (modules/secrets.nix). The NAS keeps serving the seats' sync
  # until Atuin is retired. Tom: "atuin is ok for now but i mentioned
  # previously that atuin was on its way out."
  #
  # The encryption key itself is fleet state, not per-host state: it's minted
  # once, delivered via agenix (secrets/atuin-key.age, common tier — see
  # secrets.nix), and force-copied into ~/.local/share/atuin/key on every
  # activation of a host whose home enables this client (modules/secrets.nix).
  programs.atuin = {
    enable = hostName != "nas";
    enableFishIntegration = false;
    settings = {
      auto_sync = true;
      # port must match services.atuin.port in modules/atuin.nix.
      sync_address = "http://nas:27321";
    };
  };

  # ---------------------------------------------------------------------------
  # The brain's linger keeps its user manager and Herdr panes alive without
  # a login session. modules/headless.nix preserves it on the NAS.
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # gtk/icon/cursor theming — mactahoe (overlay). GTK dirs are
  # MacTahoe-<Color>[-solid]-grey[-(x)hdpi]; icon dirs MacTahoe[-light|-dark].
  # ---------------------------------------------------------------------------
  gtk = lib.mkIf isSeat {
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
      name = if osConfig.myFleet.has "compute" then "Bibata-Modern-Amber" else "Bibata-Modern-Classic";
      package = pkgs.bibata-cursors;
    };
    # Photos gets a plain bookmark, not an XDG dir (see xdg.userDirs below):
    # XDG_PICTURES_DIR is where screenshot tools save, and /mnt/nas/photos is
    # Immich's library root — stray screenshots must not land inside it.
    gtk3.bookmarks = lib.optionals (osConfig.myFleet.has "compute") [
      "file:///mnt/nas/photos Photos"
    ];
  };

  # ---------------------------------------------------------------------------
  # NAS media in the Nautilus sidebar (strix only). Music/Videos become
  # the REAL XDG user dirs pointing into the NFS automount, so Nautilus (and
  # anything using g_get_user_special_dir) treats the NAS library as native
  # local folders; first click triggers the automount. createDirectories stays
  # off — the dirs live on the NAS and mkdir through a dead mount at HM
  # activation would hang or spray errors.
  #
  # These entries (and the Photos bookmark above) only survive into the sidebar
  # because hosts/strix/nas-client.nix warms the automount before
  # graphical-session.target: a path that isn't there when the session starts is
  # silently dropped, which is #139.
  #
  # The client keeps its browser downloads, saved screenshots and video work.
  # Other XDG application defaults stay under its data directory. Nothing here
  # eagerly creates a user directory during activation.
  # ---------------------------------------------------------------------------
  xdg.userDirs = lib.mkMerge [
    (lib.mkIf (osConfig.myFleet.has "brain") {
      enable = true;
      createDirectories = false;
      music = "/mnt/nas/music";
      videos = "/mnt/nas/videos";
    })
    (lib.mkIf (hostName == "client") (
      let
        hidden = name: "${config.xdg.dataHome}/user-dirs/${name}";
      in
      {
        enable = true;
        package = null;
        createDirectories = false;
        download = "${config.home.homeDirectory}/Downloads";
        desktop = hidden "Desktop";
        documents = hidden "Documents";
        music = hidden "Music";
        pictures = "${config.home.homeDirectory}/Pictures";
        projects = hidden "Projects";
        publicShare = hidden "Public";
        templates = hidden "Templates";
        videos = "${config.home.homeDirectory}/Videos";
      }
    ))
  ];

  # ---------------------------------------------------------------------------
  # OBS Studio — the module wraps OBS so the plugin loads. obs-vkcapture is also
  # in home.packages so its Vulkan/GL capture layer + `obs-gamecapture` helper
  # land on the user profile for capturing other Wayland apps, not just OBS.
  # ---------------------------------------------------------------------------
  programs.obs-studio = {
    enable = isSeat;
    plugins = with pkgs.obs-studio-plugins; [
      obs-vkcapture
    ];
  };

  # ---------------------------------------------------------------------------
  # user packages.
  # ---------------------------------------------------------------------------
  home.packages =
    with pkgs;
    [
      eza
      zoxide
      starship
      fzf
      bat
      ripgrep
      fd
      jq
      yq-go
      glow
      pythonForScripts
      yt-dlp
      aria2
      ffmpeg-full
      bubblewrap
      uv
    ]
    ++ lib.optionals isBrain [
      gitAiTools
      huggingface-cli
      gh
      google-cloud-sdk
      cloudflared
      wrangler
      music-acquire
      artifact-render
      artifact-deck
    ]
    ++ lib.optionals isSeat [
      google-chrome
      anthropic-webfonts
      swayidle
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
      satty
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
      mpv
      imv
      vlc
      ffmpegthumbnailer
      obs-studio-plugins.obs-vkcapture
      nautilus
      nautilus-open-any-terminal
      xdg-terminal-exec
      xarchiver
      kitty
      artifact-view
      bibata-cursors
      gst_all_1.gstreamer
      gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-good
      gst_all_1.gst-plugins-bad
      libjxl
    ];

  # nvim → implemented in ./nvim.nix (imported above).

  home.stateVersion = "26.05";
}
