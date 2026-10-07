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
# AGENTS.md carries the ordering rule.
let
  repoDir = config.rawDotfiles.repoDir;
  dots = "${repoDir}/home";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dots}/${path}";

  hostName = osConfig.networking.hostName;

  # Curated llm-agents.nix install. `pkgs.llm-agents` (from the flake input's
  # overlay) is the entire ~139-agent catalog, prebuilt against upstream's own
  # nixpkgs. The maximalist "install every buildable member" sweep (write-up
  # retired to Git history; see docs/old/README.md) surfaced a lot we neither want nor need on the
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
    "scroll" # the physical seats' compositor on scroll/transition (dawsers/scroll master)
    "niri" # kept beside scroll for rollback until niri retirement (myDisplay.keepNiri)
    "kitty"
    "ghostty" # kitty.conf's twin, read by libghostty in cmux Browser's panes
    "fish"
    "starship"
    "yt-dlp"
    "kanshi"
    "qt6ct"
  ];

  # Python interpreter backing the niri helper bin/ scripts (wifi-menu, fzf-nmcli, …).
  pythonForNiri = pkgs.python3.withPackages (
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
    ++ lib.optionals (hostName == "coordinator") [
      # CLI-Anything's generated harnesses and validation workflow assume these
      # are importable from the ordinary `python3`, not only inside cli-hub.
      click
      pytest
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
    ./browser-trust.nix
    ./ai-memory.nix
    ./ax-conwip.nix # gate OFF; defines no unit on any host. docs/ax-conwip.md
    ./client-apps.nix
    ./harness-records.nix
    ./herdr.nix
    ./nvim.nix
    ./paper.nix
    ./pi.nix
    ./piri.nix
    ./raw-dotfiles-guard.nix
    ./ssh.nix
    ./theme.nix
    ./vicinae.nix
  ];

  home.username = "tom";
  home.homeDirectory = "/home/tom";
  programs.home-manager.enable = true;

  # Every home.packages tool must be on the SESSION PATH so niri spawns and
  # kitty-daemon `kitty @ launch` children find Nix-provided binaries.
  home.sessionPath = [
    "$HOME/.nix-profile/bin"
    "$HOME/.local/bin"
  ];

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

      "sway-local.conf".text =
        lib.optionalString (hostName == "coordinator") ''
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
          bindsym --locked XF86MonBrightnessDown exec ~/.local/bin/brightness down
          bindsym --locked XF86MonBrightnessUp exec ~/.local/bin/brightness up
          bindsym --locked XF86AudioMicMute exec ~/.local/bin/volume micmute
        '';

      # Per-HOST niri config — the real per-host slot niri/local.kdl never had (that
      # file is shared by the whole-dir symlink). Emitted at a neutral ~/.config path
      # (niri/ is a whole-dir symlink, can't nest a generated file inside) and pulled
      # in by an ABSOLUTE include in niri/config.kdl (niri expands neither ~ nor $HOME).
      # Written on EVERY host (no `optional` include on the pinned niri). The
      # coordinator gets an inert file. The client — the ASUS Zenbook Duo, back
      # on 2026-09-11 — gets the ONLY per-host niri content in the fleet, and
      # this slot is the only place such content may live: niri/ itself is a
      # whole-dir RAW symlink shared by every host, so binds.kdl carries over
      # in full and the two chords that mean something different on a thin
      # client are OVERRIDDEN here. That works because config.kdl includes
      # this file last and niri's includes are positional: "binds will
      # override previously-defined conflicting keys" (niri wiki,
      # Configuration:-Include). NB: store-managed (read-only, re-emitted on
      # switch), not hot-reload RAW like the rest of niri/.
      #
      # Touch: stock niri maps every touch device to ONE output; per-device
      # mapping needs the unmerged PR #1856 and its fork build, which left the
      # tree with the old `zenbook-duo` host and does NOT come back (Tom's
      # ruling 2026-09-11: accepted defect, no fork, no ntm, no rotation). The
      # top panel is the working surface, so it gets the touch; the bottom
      # panel's touch lands on the top one until #1856 merges.
      #
      # Mod+Return / Mod+Ctrl+Shift+Return are NOT overridden here any more
      # (#385, 2026-09-13): binds.kdl's own chords call ~/.local/bin/herdr-chord,
      # which targets the coordinator through a local `herdr --remote`
      # projector, so the RAW file is already right on the client and nothing
      # needs a rebuild to re-cut them. The ssh-tty spellings that lived here
      # (`hk-new-inplace`, `hk-resume-agents`) ran the herdr client ON the
      # coordinator, where no clipboard image can ever be read.
      #
      # F10: binds.kdl's "sleep monitors" popup (power-off-monitors behind an
      # fzf prompt) becomes a popup-free BACKLIGHT toggle — brightness to zero
      # on intel_backlight, which the dock daemon copies to eDP-2 within
      # 500 ms, so one write darkens both panels; the next F10 restores the
      # saved level (or 50% if the save file under /tmp is gone). The logic
      # lives in bin/brightness (off/restore/toggle, since M-3), not inline
      # here, so the script and the key cannot drift apart. Keys keep
      # working throughout, so there is no lockout; Mod+Shift+P keeps DPMS-all.
      #
      # XF86 twins: the daemon re-emits the Duo keyboard's Fn keys as
      # XF86MonBrightnessDown/Up and XF86AudioMicMute, none of which binds.kdl
      # binds (it binds plain F-keys for the Glove80). Bound here so the
      # laptop's own keys are not dead.
      "niri-local.kdl".text =
        if hostName == "client" then
          ''
            // GENERATED per-host (home.nix). client — ASUS Zenbook Duo UX8406MA.
            input {
                touch {
                    map-to-output "eDP-1"
                }
            }

            binds {
                F10 hotkey-overlay-title="Backlight off / restore" { spawn-sh "~/.local/bin/brightness toggle"; }
                XF86MonBrightnessDown allow-when-locked=true { spawn-sh "~/.local/bin/brightness down"; }
                XF86MonBrightnessUp allow-when-locked=true { spawn-sh "~/.local/bin/brightness up"; }
                XF86AudioMicMute allow-when-locked=true { spawn-sh "~/.local/bin/volume micmute"; }
            }
          ''
        else
          ''
            // GENERATED per-host (home.nix). No host-specific niri config on ${hostName}.
          '';

      # Per-HOST scroll config: the scroll twin of niri-local.kdl, same reasons
      # (scroll/ is a whole-dir RAW symlink shared by every host). Included by
      # scroll/config after binds.conf and before the theme fragment, so the
      # client's chords override binds.conf (a later bindsym wins; --no-warn
      # silences the duplicate notice). Store-managed, re-emitted on switch.
      #
      # Touch: sway-family input blocks map PER DEVICE, which closes the
      # accepted R-10 defect niri could not (stock niri maps every touch device
      # to one output). The type-wide line keeps today's niri behaviour
      # (everything on eDP-1); the two per-device lines are the R-10 fix, left
      # commented until `scrollmsg -t get_inputs` on the client confirms which
      # ELAN panel is which (identifiers inferred from the scroll-era
      # lisgd-start device names, 0x04F3 = 1267, 0x425A/B = 16986/16987).
      #
      # Lid: niri turned eDP-1 off on lid close by itself and hosts/client/
      # lid.nix relies on that (logind ignores the lid). sway-family
      # compositors do not, so bindswitch does it; --reload re-applies the
      # state after a config reload.
      #
      # F10 / XF86: as niri-local.kdl (backlight toggle; the Duo daemon's
      # re-emitted Fn keys).
      "scroll-local.conf".text =
        if hostName == "client" then
          ''
            # GENERATED per-host (home.nix). client — ASUS Zenbook Duo UX8406MA.
            input type:touch map_to_output eDP-1
            # R-10 per-device mapping (verify ids with `scrollmsg -t get_inputs`):
            # input "1267:16986:ELAN9008:00_04F3:425A" map_to_output eDP-1
            # input "1267:16987:ELAN9008:00_04F3:425B" map_to_output eDP-2

            bindswitch --reload --locked lid:on output eDP-1 disable
            bindswitch --reload --locked lid:off output eDP-1 enable

            # @title Backlight off / restore
            bindsym --no-warn F10 exec ~/.local/bin/brightness toggle
            bindsym --locked XF86MonBrightnessDown exec ~/.local/bin/brightness down
            bindsym --locked XF86MonBrightnessUp exec ~/.local/bin/brightness up
            bindsym --locked XF86AudioMicMute exec ~/.local/bin/volume micmute
          ''
        else
          ''
            # GENERATED per-host (home.nix). No host-specific scroll config on ${hostName}.
          '';
    };
  # (The gtk-4.0/{gtk.css,gtk-dark.css,assets} links that used to sit here — a
  # store symlink of MacTahoe-Dark-grey's gtk-4.0 — moved to home/theme.nix,
  # where they point through the ~/.config/theme pointer at whichever theme's
  # MacTahoe variant is selected. 2026-09-17.)

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
  # Third account (2026-09-05): `cc3`/`cac3` → ~/.claude-3, same links.
  home.file.".claude-3/skills".source = link "dot_claude/skills";
  home.file.".claude-3/rules/runtime-tests.md".source = link "agent-runtime-rules.md";

  # settings.json is NOT a home.file: Claude Code writes it (/effort, /model,
  # /config) by resolving ONE symlink hop and renaming a temp file into that
  # directory. Through home.file the hop lands in the read-only
  # home-manager-files store dir (EROFS, 2026-10-03). Each seat instead gets a
  # direct symlink to the checkout file, so in-app changes land in
  # home/dot_claude/settings.json, shared by every seat, visible to git.
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    for seat in .claude .claude-work .claude-3; do
      run mkdir -p $VERBOSE_ARG "$HOME/$seat"
      run ln -sfn $VERBOSE_ARG "${dots}/dot_claude/settings.json" "$HOME/$seat/settings.json"
    done
  '';

  # Same canonical skill tree, exposed to Codex and `pi` (earendil-works/pi)
  # through the vendor-neutral, always-trusted Agent-Skills directory
  # (~/.agents/skills). Both read the same agentskills.io SKILL.md format
  # (name/description frontmatter, symlinks followed), so ONE tree feeds every
  # harness. pi selects on `description` only (ignores `when_to_use`), so keep
  # triggers there.
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
  # atuin — shell history, synced fleet-wide through a self-hosted server on the
  # coordinator (hosts/coordinator/services.nix), tailnet-only. The package here
  # replaces the old bare `atuin` entry in home.packages; fish's own init call +
  # the Ctrl+E rebind stay in dot_config/fish/config.fish untouched
  # (enableFishIntegration = false avoids home-manager wiring a second one).
  #
  # sync_address: the coordinator talks to its own server over localhost; every
  # other host reaches it via MagicDNS (`coordinator`, tailnet-only — see the
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
      # port must match services.atuin.port in hosts/coordinator/services.nix.
      sync_address =
        if hostName == "coordinator" then "http://localhost:27321" else "http://coordinator:27321";
    };
  };

  # ---------------------------------------------------------------------------
  # `loginctl enable-linger tom` (already set on the coordinator) is what keeps
  # user-level services running when no login session is open. The posture it
  # now serves is ONE long-lived server per user, not N daemons forked per
  # session: the coordinator hosts the single herdr server and every PTY lives
  # inside it, so a laptop that reconnects later finds its panes still alive.
  # Linger is therefore load-bearing for the coordinator alone — no other host
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
      name = if hostName == "coordinator" then "Bibata-Modern-Amber" else "Bibata-Modern-Classic";
      package = pkgs.bibata-cursors;
    };
    # Photos gets a plain bookmark, not an XDG dir (see xdg.userDirs below):
    # XDG_PICTURES_DIR is where screenshot tools save, and /mnt/nas/photos is
    # Immich's library root — stray screenshots must not land inside it.
    gtk3.bookmarks = lib.optionals (hostName == "coordinator") [
      "file:///mnt/nas/photos Photos"
    ];
  };

  # ---------------------------------------------------------------------------
  # NAS media in the Nautilus sidebar (coordinator only). Music/Videos become
  # the REAL XDG user dirs pointing into the NFS automount, so Nautilus (and
  # anything using g_get_user_special_dir) treats the NAS library as native
  # local folders; first click triggers the automount. createDirectories stays
  # off — the dirs live on the NAS and mkdir through a dead mount at HM
  # activation would hang or spray errors.
  #
  # These entries (and the Photos bookmark above) only survive into the sidebar
  # because hosts/coordinator/nas-client.nix warms the automount before
  # graphical-session.target: a path that isn't there when the session starts is
  # silently dropped, which is #139.
  # ---------------------------------------------------------------------------
  xdg.userDirs = lib.mkIf (hostName == "coordinator") {
    enable = true;
    createDirectories = false;
    music = "/mnt/nas/music";
    videos = "/mnt/nas/videos";
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

  # dcal keeps the local calendar database warm for CLI reads. Its IPC socket
  # is PID-qualified directly beneath XDG_RUNTIME_DIR; do not add a nested
  # RuntimeDirectory here because unix socket paths are limited to 108 chars.
  # Coordinator only (2026-09-11): the calendar CLI and its agents run there;
  # the thin client has no consumer, and the unit was the one fleet-wide
  # user service with no host gate at all.
  systemd.user.services.dcal-daemon = lib.mkIf (hostName == "coordinator") {
    Unit = {
      Description = "dcal calendar daemon";
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${lib.getExe pkgs.dcal} daemon";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "default.target" ];
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

    # wayland desktop tooling. xwayland-satellite: niri's X11 path — X11 apps
    # and Chrome fallbacks need it on the session PATH under niri; scroll has
    # native Xwayland. Kept while niri is the rollback (myDisplay.keepNiri).
    xwayland-satellite
    # scroll/scripts/monitors-off: sway-family compositors do not wake outputs
    # on input, so a one-shot swayidle resume does it (niri's power-off-monitors).
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

    # the python interpreter the niri helper scripts need
    pythonForNiri

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
    huggingface-cli # metadata CLI; agenix authentication is coordinator-only
    gh
    google-cloud-sdk
    gws # Google Workspace CLI (Gmail/Calendar/Drive/Sheets/Docs/...), Discovery-doc-backed
    cloudflared
    wrangler # CF Pages/DNS control plane; auth = wrangler-config.age (coordinator-only cred, binary fleet-wide)
    backlog-md # bespoke pkg via overlay — see pkgs/backlog-md.nix
    pkgs.crm # vendored personal CRM CLI; data stays at its built-in notes path
    pkgs.dcal # vendored calendar CLI; data lives under XDG, nothing in git
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
