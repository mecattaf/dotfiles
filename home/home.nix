{
  config,
  lib,
  pkgs,
  ...
}:
# home-manager — Layer 1 bridge.
#
# GOVERNING PRINCIPLE: maximal nix-native is the END-STATE. The RAW out-of-store
# symlinks below are TEMPORARY scaffolding to reach a first boot (hot-reload, no
# rebuild). Do NOT overbuild around them.
#
# REPO PRESENCE: the out-of-store symlinks point at a *cloned checkout* of this repo
# at `repoDir`. On a fresh machine the Duo runbook clones the repo there BEFORE the
# first `home-manager switch` (else the symlinks dangle until cloned).
let
  repoDir = "${config.home.homeDirectory}/mecattaf/dotfiles";
  dots = "${repoDir}/home";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dots}/${path}";

  # RAW config dirs (dotfiles-sweep RAW set, minus GONE: scroll/waybar/quickshell*/
  # containers; minus asr-rs until v2 binary ships). niri is RAW *for now* — typed
  # programs.niri.settings + niri-flake is the post-first-boot nixification.
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

  # 11 Chrome PWAs (antigravity DROPPED). flatpak chrome → google-chrome-stable --app.
  chrome = "${pkgs.google-chrome}/bin/google-chrome-stable";
  pwa = name: url: {
    inherit name;
    exec = "${chrome} --profile-directory=Default --app=${url}";
    icon = "${dots}/dot_local/share/icons/${name}.png";
    categories = [ "Network" ];
  };
in
{
  imports = [ ./nvim.nix ];

  home.username = "tom";
  home.homeDirectory = "/home/tom";
  programs.home-manager.enable = true;

  # ---------------------------------------------------------------------------
  # RAW configs (whole-dir per ~/.config/<name>) — hot-reload scaffolding.
  # ---------------------------------------------------------------------------
  xdg.configFile = lib.genAttrs configDirs (d: {
    source = link "dot_config/${d}";
  });

  # bin/ scripts: whole-dir (the repo OWNS ~/.local/bin). EVENTUAL nix-native =
  # writeShellApplication with declared deps; RAW only as interim.
  home.file.".local/bin".source = link "dot_local/bin";

  # icons for the PWA launchers (referenced by absolute path above).
  home.file.".local/share/icons/_repo".source = link "dot_local/share/icons";

  # wallpapers — whole-dir at ~/.local/share/wallpapers (wallpaper.jpg + placeholder).
  home.file.".local/share/wallpapers".source = link "dot_local/share/wallpapers";

  # bash login files (RAW). NB: dot_bashrc sources ~/.env (secrets) — deferred to the
  # secrets session; until then it's a harmless missing-file warning.
  home.file.".bashrc".source = link "dot_bashrc";
  home.file.".bash_profile".source = link "dot_bash_profile";

  # ---------------------------------------------------------------------------
  # PWA launchers (TYPED via xdg.desktopEntries; google-chrome, not flatpak).
  # ---------------------------------------------------------------------------
  xdg.desktopEntries = {
    chatgpt = pwa "chatgpt" "https://chat.openai.com/";
    claude = pwa "claude" "https://claude.ai/";
    gcloud = pwa "gcloud" "https://drive.google.com/drive/u/0/";
    github = pwa "github" "https://github.com/mecattaf";
    "open-webui" = pwa "open-webui" "http://localhost:8080/";
    perplexity = pwa "perplexity" "https://perplexity.ai/";
    photos = pwa "photos" "https://photos.google.com/";
    railway = pwa "railway" "https://railway.app/dashboard";
    soundcloud = pwa "soundcloud" "https://soundcloud.com";
    whatsapp = pwa "whatsapp" "https://web.whatsapp.com/";
    "youtube-music" = pwa "youtube-music" "https://music.youtube.com";
  };

  # ---------------------------------------------------------------------------
  # git — the ONE typed config (replaces the chezmoi dot_gitconfig.tmpl).
  # ---------------------------------------------------------------------------
  programs.git = {
    enable = true;
    settings = {
      user.name = "mecattaf";
      user.email = "thomas@mecattaf.dev";
      init.defaultBranch = "main";
      credential.helper = "${pkgs.gh}/bin/gh auth git-credential";
    };
  };

  # ---------------------------------------------------------------------------
  # gtk/icon/cursor theming — the proven mactahoe (overlay). Theme dir names are
  # install.sh outputs; verify exact names on first build (cosmetic if slightly off).
  # ---------------------------------------------------------------------------
  gtk = {
    enable = true;
    theme = {
      name = "MacTahoe-grey-dark";
      package = pkgs.mactahoe-gtk-theme;
    };
    iconTheme = {
      name = "MacTahoe-grey-dark";
      package = pkgs.mactahoe-icon-theme;
    };
    cursorTheme = {
      name = "Bibata-Modern-Classic";
      package = pkgs.bibata-cursors;
    };
  };

  # ---------------------------------------------------------------------------
  # OBS Studio — nix-native replacement for the harness flatpaks
  # (com.obsproject.Studio + …Plugin.OBSVkCapture). The module wraps OBS so the
  # plugin loads; obs-vkcapture is ALSO listed in home.packages below so the
  # Vulkan/GL capture layer + `obs-gamecapture` helper land on the user profile
  # (XDG_DATA_DIRS / PATH) for capturing other Wayland apps, not just OBS itself.
  # ---------------------------------------------------------------------------
  programs.obs-studio = {
    enable = true;
    plugins = with pkgs.obs-studio-plugins; [
      obs-vkcapture
    ];
  };

  # ---------------------------------------------------------------------------
  # user packages — built from harness-sweep §Packages + harnessRPM ledger +
  # dotfiles-sweep bin/ deps (the SAME-bucket set + the daily drivers).
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

    # niri / wayland desktop tooling + D2 native re-point (brightnessctl/playerctl/
    # swaybg; NO rofi by decision)
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

    # screen/game recording (OBS itself is wired via programs.obs-studio above);
    # this exposes the vkcapture host layer + obs-gamecapture launcher on PATH.
    obs-studio-plugins.obs-vkcapture

    # files / nautilus + open-any-terminal (decided keep)
    nautilus
    nautilus-open-any-terminal
    xdg-terminal-exec

    # session persistence + terminal
    shpool
    kitty

    # agent / dev tooling (pi.nix + llm-agents.nix come in the agent session)
    gh
    google-cloud-sdk
    cloudflared

    # cursors (theme dep)
    bibata-cursors

    # codecs/gstreamer plugins for thumbnailers + portals
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
  ];

  # nvim → implemented in ./nvim.nix (imported above): programs.neovim + lazy-nix-helper
  # store-resolution + mason→Nix marksman + treesitter pre-seed.
  #
  # DEFERRED (own sessions / post-boot, tracked — NOT dropped):
  #   - Claude Code + pi config → the AI-agent nix flake (llm-agents.nix / pi.nix), NOT
  #     hand-rolled COPY (per the ratified refinement)
  #   - asr-rs v2, the ~/.env secrets, skills/ → their own sessions

  home.stateVersion = "26.05";
}
