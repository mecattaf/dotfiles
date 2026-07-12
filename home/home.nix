{
  config,
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
let
  repoDir = "${config.home.homeDirectory}/mecattaf/dotfiles";
  dots = "${repoDir}/home";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dots}/${path}";

  # Curated llm-agents.nix install. `pkgs.llm-agents` (from the flake input's
  # overlay) is the entire ~139-agent catalog, prebuilt against upstream's own
  # nixpkgs. The maximalist "install every buildable member" sweep (see
  # docs/llm-agents-catalog.md) surfaced a lot we neither want nor need on the
  # desktop, so we've pruned to an explicit ALLOWLIST — only these names are
  # pulled from the catalog. Adding an agent is now a deliberate edit here, and
  # agents upstream adds no longer land automatically on `nix flake update`.
  #
  # backlog-md is DELIBERATELY absent from this list: we build our own at top
  # level (pkgs/backlog-md.nix, bin/backlog) and pulling it from the catalog too
  # would double-load and collide on the same binary. One source only.
  #
  # `meta.available` filtering (wrapped in tryEval, since evaluating meta can
  # itself throw) skips any keeper that's broken / wrong-platform on this host.
  # claude-code comes FROM this set, so it has no standalone home.packages entry.
  keepFromLlmAgents = [
    "claude-code"
    "ccusage"
    "ck"
    "claude-agent-acp"
    "qmd"
    "pi"
  ];
  llmAgentsSelected = pkgs.buildEnv {
    name = "llm-agents-selected";
    # Curated set is small, but a couple of members still share share/ paths;
    # keep ignoreCollisions so the profile merges deterministically (first wins).
    ignoreCollisions = true;
    paths = lib.pipe pkgs.llm-agents [
      (lib.filterAttrs (n: _: builtins.elem n keepFromLlmAgents))
      (lib.filterAttrs (
        _: v: (builtins.tryEval (lib.isDerivation v && (v.meta.available or true))).value
      ))
      builtins.attrValues
    ];
  };

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
    "cliamp"
  ];
  # NB: zmx has no config file (unlike shpool) — nothing to symlink here.

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
    ./tally.nix
  ];

  home.username = "tom";
  home.homeDirectory = "/home/tom";
  programs.home-manager.enable = true;

  # Every home.packages tool must be on the SESSION PATH so niri spawns and
  # kitty-daemon `kitty @ launch` children find Nix-provided binaries.
  home.sessionPath = [ "$HOME/.nix-profile/bin" "$HOME/.local/bin" ];

  # Claude Code reads its config/creds from $CLAUDE_CONFIG_DIR (defaults to ~/.claude).
  # modules/secrets.nix seeds the OAuth credential to ~/.claude-main, so point Claude
  # Code there — otherwise the seeded cred lands where nothing reads it and Claude Code
  # re-prompts for OAuth on a fresh box despite the secret being delivered.
  home.sessionVariables.CLAUDE_CONFIG_DIR = "${config.home.homeDirectory}/.claude-main";
  # Force the file backend explicitly so gws never guesses between it and an
  # OS keyring (GNOME keyring/kwallet) — the agenix-delivered .encryption_key
  # only makes sense if gws is always in file mode. See gws-*.age in secrets.nix.
  home.sessionVariables.GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND = "file";

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

      # asr-rs dictation — the ONE per-host config in this file (branching on
      # hostname, same pattern as remote.nix). The coordinator hosts the
      # Parakeet models and serves the engine to the tailnet (firewalled to
      # tailscale0:8762 in hosts/coordinator); the zenbook-duo is a thin client
      # dictating against it over MagicDNS; everything else defaults to
      # loopback. Hold-SUPER+SPACE push-to-talk everywhere: while IDLE the
      # chord is watched passively (no grab, no timers), so asr-rs is
      # entirely out of the plain-typing path — bare hold-SPACE needed a
      # permanent grab that buffered every space press and mangled fast
      # typing. WHILE DICTATING asr-rs grabs the keyboard and synthesizes the
      # chord's release to niri, so TDT-finalized segments STREAM into the
      # focused window at each speech pause, mid-hold, without becoming
      # Mod+letter binds. Mic pinned to the iContact USB webcam on the
      # coordinator only (device-specific, so it lives here, not the repo;
      # resolved via the ALSA card table — the card id is "Pro").
      #
      # No focus_guard: it existed to keep hold-SPACE from fighting Claude
      # Code's own held-space voice mode, but it also silently ate dictation
      # in any window running a local claude. A deliberate SUPER+SPACE chord
      # can't collide with plain space, so dictation now works everywhere.
      # niri's Mod+Space is a consume-only no-op bind (see niri/binds.kdl).
      "asr-rs/config.toml".text =
        let
          host = osConfig.networking.hostName;
          ptt = ''
            [push_to_talk]
            enabled = true
            key = "SUPER+SPACE"
          '';
        in
        if host == "coordinator" then
          ''
            [engine]
            bind = "0.0.0.0:8762"   # scoped by the tailscale0-only firewall rule

            [audio]
            device = "iContact"     # USB webcam mic (high-quality intake)

          ''
          + ptt
        else if host == "zenbook-duo" then
          ''
            [engine]
            url = "ws://coordinator:8762"   # models run on the coordinator

          ''
          + ptt
        else
          ptt;
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

  # Same canonical skill tree, exposed to the `pi` agent (earendil-works/pi) via
  # its vendor-neutral, always-trusted Agent-Skills dir (~/.agents/skills). pi
  # reads SKILL.md in the identical agentskills.io format (name/description
  # frontmatter, symlinks followed), so ONE tree feeds both harnesses — the C9
  # "discoverable by both .claude and .pi" ruling, realized declaratively. pi
  # selects on `description` only (ignores `when_to_use`), so keep triggers there.
  home.file.".agents/skills".source = link "dot_claude/skills";

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
  # zmx — LOCAL session persistence. No systemd plumbing: unlike shpool's single
  # socket-activated daemon, zmx is daemon-PER-session, forked from the CLI on
  # first `attach` (setsid + XDG_RUNTIME_DIR socket). `loginctl enable-linger
  # tom` (already set on the coordinator) keeps those per-session daemons alive
  # across logout, so a laptop can re-`kitten ssh` in and re-attach any time. See
  # home.packages below for the binary, and home/dot_local/bin/zmx-resume for the
  # picker.
  # ---------------------------------------------------------------------------

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
    # dictation — dual-Parakeet STT daemon (spawn-at-startup in niri/startup.kdl;
    # binds in niri/binds.kdl; per-host config generated above)
    asr-rs

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

    # session persistence + terminal. zmx (overlay pkg via flake input) is the
    # projector primitive — persistent LOCAL sessions, reached over kitten ssh
    # from laptops.
    zmx
    kitty

    # agent / dev tooling. A curated slice of the llm-agents.nix catalog
    # (claude-code, ccusage, ck, claude-agent-acp, qmd, pi) lands via
    # llmAgentsSelected — see the allowlist buildEnv in the `let` block above.
    # claude-code comes from there (newest, decoupled from nixpkgs); creds still
    # seed via modules/secrets.nix, and DISABLE_UPDATES=1 keeps the native
    # updater from clobbering ~/.local/bin.
    llmAgentsSelected
    gh
    google-cloud-sdk
    gws # Google Workspace CLI (Gmail/Calendar/Drive/Sheets/Docs/...), Discovery-doc-backed
    cloudflared
    wrangler # CF Pages/DNS control plane; auth = wrangler-config.age (coordinator-only cred, binary fleet-wide)
    backlog-md # bespoke pkg via overlay — see pkgs/backlog-md.nix
    cliamp # terminal music player → navidrome. overlay pkg, see pkgs/cliamp.nix

    # artifact system (md-artifact / presentation-beta / publish-artifact skills;
    # knobs in modules/artifacts-defaults.nix). render = md→snapshot dir;
    # view = bounded chrome --app window (rung 0, no publish); deck-init =
    # scaffold reveal deck with nix-vendored assets (no CDN).
    artifact-render
    artifact-view
    artifact-deck

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
