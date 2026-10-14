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
# rawDotfiles.inStore (the client) gets the same files from the Nix store and
# has no checkout (./raw-dotfiles-guard.nix).
let
  link = config.lib.rawDotfiles.link;

  hostName = osConfig.networking.hostName;

  # Curated llm-agents.nix install. `pkgs.llm-agents` (from the flake input's
  # overlay) is the entire ~139-agent catalog, prebuilt against upstream's own
  # nixpkgs. The maximalist "install every buildable member" sweep (write-up
  # retired to Git history; see docs/old/README.md) surfaced a lot we neither want nor need on the
  # desktop, so we've pruned to an explicit ALLOWLIST — only these names are
  # pulled from the catalog. Adding an agent is now a deliberate edit here, and
  # agents upstream adds no longer land automatically on `nix flake update`.
  #
  # `meta.available` filtering (wrapped in tryEval, since evaluating meta can
  # itself throw) skips any keeper that's broken / wrong-platform on this host.
  # claude-code comes FROM this set, so it has no standalone home.packages entry.
  keepFromLlmAgents = [
    "claude-code"
    "ccusage"
    "ck"
    "claude-agent-acp"
    "claude-code-router" # bin: `ccr` — routes Claude Code requests to other model backends/providers
    "qmd"
    # NB: `pi` is intentionally absent — home/pi.nix ships a wrapped `pi` (real
    # binary + declarative extension roster) as the sole `pi` on PATH. Keeping it
    # here too would double-provide bin/pi and collide in the profile.
    "codex"
    "spec-kit" # bin: `specify` — GitHub Spec-Kit, spec-driven development bootstrapper
    "cc-switch-cli" # bin: `cc-switch` — switches Claude Code/Codex/Gemini CLI provider configs
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
    "sway" # shared physical desktop
    "kitty"
    "ghostty" # kitty.conf's twin, read by libghostty in cmux Browser's panes
    "fish"
    "starship"
    "yt-dlp"
    "kanshi"
    "qt6ct"
  ];

  # Python interpreter backing the helper bin/ scripts (wifi-menu, fzf-nmcli, …).
  pythonForScripts = pkgs.python3.withPackages (
    ps:
    with ps;
    [
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
    ++ lib.optionals (hostName == "strix") [
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
    ./ai-memory.nix
    ./client-apps.nix
    ./harness-records.nix
    ./herdr.nix
    ./nvim.nix
    ./paper.nix
    ./pi.nix
    ./raw-dotfiles-guard.nix
    ./ssh.nix
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
    // {
      # kitty/ is a whole-dir out-of-store symlink, so the store-path fragment can't
      # nest inside it — emit at a neutral path; kitty.conf includes it by absolute
      # (env-expanded) path.
      "kitty-scrollback-nix.conf".text = ''
        # GENERATED — Nix-store path for kitty-scrollback.nvim kittens (offline-safe).
        action_alias kitty_scrollback_nvim kitten ${pkgs.vimPlugins.kitty-scrollback-nvim}/python/kitty_scrollback_nvim.py
      '';

      "sway-local.conf".text =
        lib.optionalString (hostName == "strix") ''
          output DP-4 scale 2 position 0 0
          output DP-1 scale 2 position 2560 0
        ''
        + lib.optionalString (hostName == "client") ''
          # Zenbook Duo: logical 1440x900 panels, vertically stacked.
          output eDP-1 scale 2 position 0 0
          output eDP-2 scale 2 position 0 900
          # Preserve the verified top-panel mapping until both device IDs are
          # measured on this laptop. Do not turn inferred ELAN IDs into policy.
          input type:touch map_to_output eDP-1
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
  dconf.settings."org/gnome/desktop/interface" = {
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
  home.file.".local/bin".source = link "dot_local/bin";

  # icons for the PWA launchers (referenced by absolute path above).
  home.file.".local/share/icons/_repo".source = link "dot_local/share/icons";

  # wallpapers — whole-dir at ~/.local/share/wallpapers (wallpaper.jpg + placeholder).
  home.file.".local/share/wallpapers".source = link "dot_local/share/wallpapers";

  # One stable $HOME path the docs can name for the Anthropic woff2 + CSS, since
  # the real one is the profile path /etc/profiles/per-user/tom/share/webfonts.
  # Measured safe 2026-09-17: fontconfig's only xdg directory is
  # `<dir prefix="xdg">fonts</dir>` (/etc/fonts/fonts.conf:104), i.e.
  # ~/.local/share/fonts EXACTLY — so a sibling named `webfonts` is not scanned.
  # DO NOT rename this to `fonts`.
  home.file.".local/share/webfonts".source = "${pkgs.anthropic-webfonts}/share/webfonts";

  # bash login files. dot_bashrc sources ~/.env (secrets) — harmless missing-file
  # warning until that file exists.
  home.file.".bashrc".source = link "dot_bashrc";
  home.file.".bash_profile".source = link "dot_bash_profile";

  # Claude Code skills + settings in the standard user config directory.
  # Deployed as individual out-of-store symlinks — NOT a whole-dir link — so
  # ~/.claude stays a real, writable directory that modules/secrets.nix can seed
  # .credentials.json into (a whole-dir symlink would push the credential into the
  # PUBLIC repo tree). Without this, a fresh box has zero skills/settings.
  home.file.".claude/skills".source = link "dot_claude/skills";
  home.file.".claude/rules/runtime-tests.md".source = link "agent-runtime-rules.md";
  home.file.".codex/AGENTS.md".source = link "agent-runtime-rules.md";

  # NO hook is delivered here any more. The SessionEnd harvest hook (MEM-2,
  # dotfiles#339) was removed 2026-09-23: it blocked session exit for up to 57 s
  # on the runs that actually harvested, and Claude Code reported the abort as
  # "SessionEnd hook [...] failed: Hook cancelled" on every close. Of its last
  # 101 logged runs, 54 were skips. The harvest verb itself is unchanged and
  # still reachable on demand through the `drain` skill.
  #
  # ~/.claude/hooks is deliberately left as a real, writable directory owned by
  # nobody: a hook that is not delivered from this repository can still live
  # there (the dead SessionStart hook that once named herdr-agent-state.sh was
  # removed the same way, 2026-09-13).

  # Second Claude account (work): `cc2`/`cac2` in fish set CLAUDE_CONFIG_DIR to
  # ~/.claude-work. Same skills + settings, separate .credentials.json/.claude.json.
  home.file.".claude-work/skills".source = link "dot_claude/skills";
  home.file.".claude-work/rules/runtime-tests.md".source = link "agent-runtime-rules.md";

  # Claude owns mutable preferences. One direct symlink hop reaches writable
  # shared state, never the Nix store or Git checkout. Activation seeds only
  # once and preserves /model and /effort changes on every later switch.
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${pkgs.python3}/bin/python3 ${./claude-settings.py} \
      --home "$HOME" --template ${./dot_claude/settings.json}
  '';

  # Same canonical skill tree, exposed to Codex and `pi` (earendil-works/pi)
  # through the vendor-neutral, always-trusted Agent-Skills directory
  # (~/.agents/skills). Both read the same agentskills.io SKILL.md format
  # (name/description frontmatter, symlinks followed), so ONE tree feeds every
  # harness. pi selects on `description` only (ignores `when_to_use`), so keep
  # triggers there.
  home.file.".agents/skills".source = link "dot_claude/skills";

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
  # atuin — shell history, synced fleet-wide through a self-hosted server on the
  # strix (hosts/strix/services.nix), tailnet-only. The package here
  # replaces the old bare `atuin` entry in home.packages; fish's own init call +
  # the Ctrl+E rebind stay in dot_config/fish/config.fish untouched
  # (enableFishIntegration = false avoids home-manager wiring a second one).
  #
  # sync_address: the strix talks to its own server over localhost; every
  # other host reaches it via MagicDNS (`strix`, tailnet-only — see the
  # firewall rule on the server side).
  #
  # The encryption key itself is fleet state, not per-host state: it's minted
  # once, delivered via agenix (secrets/atuin-key.age, common tier — see
  # secrets.nix), and force-copied into ~/.local/share/atuin/key on every
  # activation (modules/secrets.nix) so every host decrypts the same history.
  programs.atuin = {
    enable = true;
    enableFishIntegration = false;
    settings = {
      auto_sync = true;
      # port must match services.atuin.port in hosts/strix/services.nix.
      sync_address = if hostName == "strix" then "http://localhost:27321" else "http://strix:27321";
    };
  };

  # ---------------------------------------------------------------------------
  # `loginctl enable-linger tom` (already set on the strix) is what keeps
  # user-level services running when no login session is open. The posture it
  # now serves is ONE long-lived server per user, not N daemons forked per
  # session: the strix hosts the single herdr server and every PTY lives
  # inside it, so a laptop that reconnects later finds its panes still alive.
  # Linger is therefore load-bearing for the strix alone — no other host
  # runs a server (ruling B5/B6).
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
      name = if hostName == "strix" then "Bibata-Modern-Amber" else "Bibata-Modern-Classic";
      package = pkgs.bibata-cursors;
    };
    # Photos gets a plain bookmark, not an XDG dir (see xdg.userDirs below):
    # XDG_PICTURES_DIR is where screenshot tools save, and /mnt/nas/photos is
    # Immich's library root — stray screenshots must not land inside it.
    gtk3.bookmarks = lib.optionals (hostName == "strix") [
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
  # The client (2026-10-11): Tom wants its home CLEAN, Downloads (Chrome's) and
  # hidden dirs only. Nothing creates the user dirs (createDirectories off, no
  # xdg-user-dirs package, so no xdg-user-dirs-update either), Downloads stays
  # where Chrome expects it, and every other XDG user dir points under the
  # hidden ~/.local/share/user-dirs/: an app that saves into "Pictures" or
  # "Videos" by the XDG default no longer makes ~/Pictures or ~/Videos.
  # Screenshots and call recordings do not use these at all on the client;
  # they leave for the strix (bin/screenshot, bin/call-record).
  # ---------------------------------------------------------------------------
  xdg.userDirs = lib.mkMerge [
    (lib.mkIf (hostName == "strix") {
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
        pictures = hidden "Pictures";
        projects = hidden "Projects";
        publicShare = hidden "Public";
        templates = hidden "Templates";
        videos = hidden "Videos";
      }
    ))
  ];

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

    # Anthropic woff2 + the @font-face sheet. Installed path is
    # /etc/profiles/per-user/tom/share/webfonts/{woff2,css} — NOT
    # ~/.nix-profile/share/webfonts. flake.nix sets
    # home-manager.useUserPackages = true (with useGlobalPkgs = true), which
    # routes home.packages through users.users.tom.packages; home-manager
    # creates no ~/.nix-profile at all, and the one that exists on this box is
    # an unrelated imperative `nix profile` holding only brave. Verified
    # 2026-09-17 on five packages already in this list (eza, zoxide, glow,
    # bat, fd): all five resolve under /etc/profiles/per-user/tom/bin and
    # none under ~/.nix-profile/bin. Do not "correct" this back.
    #
    # NOT in fonts.packages: see the comment in modules/common.nix.
    # home-manager's generated ~/.config/fontconfig/conf.d/10-hm-fonts.conf
    # adds only <profile>/share/fonts and <profile>/lib/X11/fonts, so
    # share/webfonts is never indexed and cannot contend with the installed
    # TTFs (re-verified against the built package: 13 fc-list rows, all from
    # the control TTF, zero woff2; adding share/webfonts yields 15 extra
    # woff2 rows). This entry is also the only thing that pulls the
    # derivation into a host closure, so attic caches it and the nightly
    # builds it.
    anthropic-webfonts

    # fish init + shell
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

    # wayland desktop tooling (Sway has native Xwayland).
    # bin/monitors-off: Sway does not wake outputs on input, so a one-shot
    # swayidle resume does it.
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
    # annotates area/window screenshots (bin/screenshot)
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

    # the python interpreter the helper scripts need
    pythonForScripts

    # media / viewers
    yt-dlp
    aria2
    mpv
    imv
    vlc
    ffmpeg-full
    ffmpegthumbnailer

    # screen/game recording — exposes the vkcapture host layer + obs-gamecapture on PATH.
    obs-studio-plugins.obs-vkcapture

    # files / nautilus + open-any-terminal + archive GUI
    nautilus
    nautilus-open-any-terminal
    xdg-terminal-exec
    xarchiver

    # terminal
    kitty

    # agent / dev tooling. A curated slice of the llm-agents.nix catalog
    # (claude-code, ccusage, ck, claude-agent-acp, qmd, pi, codex, spec-kit) lands via
    # llmAgentsSelected — see the allowlist buildEnv in the `let` block above.
    # claude-code comes from there (newest, decoupled from nixpkgs); creds still
    # seed via modules/secrets.nix, and DISABLE_UPDATES=1 keeps the native
    # updater from clobbering ~/.local/bin.
    llmAgentsSelected
    # runtime-test masks live /run/user sockets during shell/compositor tests.
    bubblewrap
    # Upstream's minimal flake output: git-ai + git-og, while programs.git below
    # remains the sole provider of the real git binary.
    inputs.git-ai.packages.${pkgs.stdenv.hostPlatform.system}.minimal
    huggingface-cli # metadata CLI; agenix authentication is strix-only
    gh
    google-cloud-sdk
    cloudflared
    wrangler # CF Pages/DNS control plane; auth = wrangler-config.age (strix-only cred, binary fleet-wide)
    music-acquire # evidence-gated SoundCloud → YouTube → capture acquisition
    uv # Astral Python pkg/project manager. "hot" overlay pkg — rides nixpkgs-fresh HEAD (flake.nix), so it stays latest independent of the main pin.

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
