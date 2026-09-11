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
let
  repoDir = "${config.home.homeDirectory}/mecattaf/dotfiles";
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
    ./ai-memory.nix
    ./client-apps.nix
    ./harness-records.nix
    ./herdr.nix
    ./nvim.nix
    ./paper.nix
    ./pi.nix
    ./piri.nix
    ./seat-feeder.nix
    ./ssh.nix
    ./tally.nix
    ./tally-filler.nix
    ./tally-pump.nix
    ./tally-uplink.nix
    ./util-sampler.nix
    ./voxtype.nix
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
      # Mod+Return: the same workspace hop as binds.kdl, then a plain
      # `ssh -t coordinator` running `hk-new-inplace` (dot_local/bin) — a NEW
      # herdr workspace + root pane on the coordinator, attached in this ssh
      # session's own tty. Superseded 2026-09-11 (Tom: "it gives me another
      # instance of that same model[.] i want it to spawn a new terminal"):
      # the old `kitty -e hk ssh --in-place coordinator` opened a second VIEW
      # of herdr's one thin-client session (`herdr --remote`, its own virtual
      # tabs) — every press landed on the SAME session, never a new one.
      # `hk new` itself can't run here: it launches its attaching kitty window
      # through kitty remote control, which needs a kitty socket on the box
      # doing the launching — the coordinator, over a plain ssh tty, has none.
      # `hk-new-inplace` is the other half of what `hk new` does when kitty IS
      # available (`cmd_new`, herdr-kitten hk/verbs.py): `hk new --no-window`
      # creates the workspace + pane without trying to launch anything, then
      # `herdr terminal attach <terminal_id>` makes THIS tty the pane's
      # surface — no kitty socket needed on the coordinator, only `herdr`
      # itself, already there for the server. Closing the kitty window this
      # runs in only detaches (client sleep, ssh drop, kitty quit); the
      # workspace and its pane are the server's problem and outlive it, which
      # is exactly what makes the resume chord below meaningful. `hk new` is
      # still meaningless as a LOCAL verb here (no local server); Mod+Shift+
      # Return stays the plain local fish.
      #
      # Mod+Ctrl+Shift+Return: binds.kdl's own resume chord (`kitty -e hk
      # resume`) is a no-op on the client — there is no local herdr server for
      # a local `hk resume` to query — so it is overridden the same way, into
      # `ssh -t coordinator hk-resume-agents` (dot_local/bin): `hk resume`'s
      # picker over the coordinator's detached panes, RESTRICTED to the panes
      # herdr sees an agent in (working / idle / blocked) and labelled with the
      # pane's own title — the conversation name for Claude Code / codex. A
      # bare shell left by a dropped ssh session, or a conversation exited by
      # hand before the window closed, is not a session to come back to (Tom
      # 2026-09-11, #355 role A) and never appears; `hk-prune-shells` closes
      # those workspaces. fzf if present, a numbered menu otherwise, execing
      # the attach in place exactly as `hk resume` does locally. This is how a
      # workspace opened above and later detached (the client went to sleep
      # mid-agent-run) comes back.
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
                Mod+Return hotkey-overlay-title="Terminal (new, on coordinator)" { spawn-sh "niri msg action focus-workspace \"$(niri msg -j workspaces | jq -re 'map(select(.is_focused))[0].output as $o | map(select(.output == $o)) | max_by(.idx) | .idx')\"; exec kitty -e ssh -t coordinator hk-new-inplace"; }
                Mod+Ctrl+Shift+Return hotkey-overlay-title="Terminal (resume, on coordinator)" { spawn "kitty" "-e" "ssh" "-t" "coordinator" "hk-resume-agents"; }
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
    # Interface fonts for Nautilus and every other GTK app that reads
    # font-name. sf-pro ships system-wide via modules/common.nix fonts.packages
    # (the one apple-fonts family kept in the 2026-08-21 sweep — "too good to
    # have"); before this key was set at all, GTK fell back to Adwaita Sans —
    # the "odd Nautilus font" on first boot.
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

  # Claude Code skills + settings in the standard user config directory.
  # Deployed as individual out-of-store symlinks — NOT a whole-dir link — so
  # ~/.claude stays a real, writable directory that modules/secrets.nix can seed
  # .credentials.json into (a whole-dir symlink would push the credential into the
  # PUBLIC repo tree). Without this, a fresh box has zero skills/settings.
  home.file.".claude/skills".source = link "dot_claude/skills";
  home.file.".claude/settings.json".source = link "dot_claude/settings.json";

  # SessionEnd -> the harvest verb (MEM-2, dotfiles#339). ONE link, not a
  # whole-dir one, for the same reason as the lines above: ~/.claude/hooks must
  # stay a real directory, because herdr's own SessionStart hook is a raw file
  # that lives there and is not delivered from this repository. settings.json is
  # shared by all three Claude config dirs and names this hook by ABSOLUTE path,
  # so one link serves ~/.claude, ~/.claude-work and ~/.claude-3 alike.
  home.file.".claude/hooks/ai-memory-harvest.sh".source =
    link "dot_claude/hooks/ai-memory-harvest.sh";

  # Second Claude account (work): `cc2`/`cac2` in fish set CLAUDE_CONFIG_DIR to
  # ~/.claude-work. Same skills + settings, separate .credentials.json/.claude.json.
  home.file.".claude-work/skills".source = link "dot_claude/skills";
  home.file.".claude-work/settings.json".source = link "dot_claude/settings.json";
  # Third account (2026-09-05): `cc3`/`cac3` → ~/.claude-3, same links.
  home.file.".claude-3/skills".source = link "dot_claude/skills";
  home.file.".claude-3/settings.json".source = link "dot_claude/settings.json";

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
      name = "Bibata-Modern-Classic";
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
  home.packages =
    with pkgs;
    [
      # browser
      google-chrome

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

      # terminal
      kitty

      # agent / dev tooling. A curated slice of the llm-agents.nix catalog
      # (claude-code, ccusage, ck, claude-agent-acp, qmd, pi, codex, spec-kit) lands via
      # llmAgentsSelected — see the allowlist buildEnv in the `let` block above.
      # claude-code comes from there (newest, decoupled from nixpkgs); creds still
      # seed via modules/secrets.nix, and DISABLE_UPDATES=1 keeps the native
      # updater from clobbering ~/.local/bin.
      llmAgentsSelected
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
      cliamp # terminal music player → navidrome. overlay pkg, see pkgs/cliamp.nix
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
    ]
    ++ lib.optionals (hostName == "coordinator") [
      # Reference CLI for the local Fara1.5 computer-use model (overlay pkg,
      # see pkgs/fara-cli.nix). Drives a real Chromium tab via Playwright;
      # point it at the llama-server you started by hand on the borrowed
      # fara15-9b-q8-0 + mmproj (docs/local-ai/README.md), e.g.:
      #   fara-cli --base_url http://localhost:8080/v1 --model fara1.5-9b --task "..."
      fara-cli
    ];

  # nvim → implemented in ./nvim.nix (imported above).

  home.stateVersion = "26.05";
}
