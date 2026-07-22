{
  pkgs,
  lib,
  config,
  ...
}:
# Device-agnostic layer — every host imports this. Use lib.mkDefault for
# anything a host or nixos-hardware module may override.
{
  imports = [
    ./mesh.nix # SSH mesh trust (known_hosts + authorized_keys)
    ./secrets.nix # agenix secret delivery (gated by mySecrets.enable, default off)
    ./dotfiles-bootstrap.nix # ensure ~/mecattaf/dotfiles exists before the session
    ./artifacts.nix # myArtifacts options (+ worker VM-port window); serving plane is coordinator-only (caddy-artifacts.nix)
  ];

  # --- identity / base ---
  networking.networkmanager.enable = true;
  time.timeZone = lib.mkDefault "Europe/Paris";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
  system.nixos.distroName = "tombionix";
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
  boot.plymouth.enable = true;
  # Many long-lived per-user watchers (persistent terminal sessions, file
  # watchers, dev tooling) exhaust the default 128 inotify instances; raise it.
  boot.kernel.sysctl."fs.inotify.max_user_instances" = 512;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;

    # Fleet-deploy hardening: a dead substituter (coordinator down, Zenbook
    # off-tailnet) must delay an unattended build by seconds, not hang it; and a
    # transfer that dies midway must fall back to building rather than fail closed.
    connect-timeout = 5;
    fallback = true;

    # Trusted Nix users (fleet-wide). Lets `tom` (via @wheel) copy in
    # worker-built, unsigned store paths (`nix copy` / `nixos-rebuild
    # --build-host` copy-back) and pass client-specified substituters — both of
    # which the daemon otherwise refuses for a non-trusted user ("lacks a
    # signature by a trusted key" / "you are not a trusted user"). Also what the
    # fleet binary cache (#42) needs to push/pull unsigned paths as tom.
    # Acceptable on this single-operator fleet: tom already has passwordless sudo.
    trusted-users = [
      "root"
      "@wheel"
    ];

    # numtide binary cache — serves the llm-agents.nix catalog (flake input) as
    # prebuilt binaries. Without it, installing the ~100-agent set would build
    # each from source; with it they're fetched. Key from the upstream flake's
    # nixConfig.
    # numtide → the llm-agents catalog; nix-amd-ai → prebuilt XRT/FastFlowLM for
    # the coordinator's NPU; hellas → its gfx1151/TheRock package graph. Both AMD
    # flakes keep their own nixpkgs/provider pins, so daemon-level cache trust —
    # NOT a flake-local nixConfig — is what avoids multi-hour source builds.
    extra-substituters = [
      "https://cache.numtide.com"
      "https://nix-amd-ai.cachix.org"
      "https://cache.hellas.ai"
      # Fleet binary cache — atticd on the coordinator (hosts/coordinator/attic.nix),
      # over the Tailscale mesh (MagicDNS `coordinator`; the Strix pair could also
      # use the TB5 fast lane `coordinator-tb`). The `fleet` cache is made public at
      # bootstrap so pulls need no per-client token/netrc — only the signing key
      # below. A cold host substitutes the ~7,744 llm-agents paths from here instead
      # of the ~8h from-source build. refs #42.
      "http://coordinator:8080/fleet"
    ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "nix-amd-ai.cachix.org-1:F4OU4vw/lV2oiG6SBHZ+nqjl4EFJuqI4X9A7pvaBmhQ="
      "cache.hellas.ai-1:PYolh95U/Ms5fKE+NQTcNZUHyEv4QikaNocg9I9iy0g="
      # fleet cache signing key — the `fleet:...=` line from `attic cache info fleet`.
      # RUNTIME BOOTSTRAP: unknown until the cache is created on first server boot
      # (attic generates the keypair server-side), so it is added here once, after:
      #   attic cache create fleet && attic cache configure fleet --public
      #   attic cache info fleet   # copy the public key line below, then rebuild
      # Until then the substituter above is inert (nix won't trust its signatures) —
      # safe: hosts just fall back to building. See hosts/coordinator/attic.nix.
      "fleet:G5pAUpKmPtVsYbhFZAQsUUcuKHGsrHo9CFAJG7x5jNM="
    ];
  };

  # A nightly candidate creates one generation per participating host. Keep two
  # weeks of local rollback depth, including deploy-rs' immediately prior target.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # --- user ---
  users.users.tom = {
    isNormalUser = true;
    description = "tom";
    extraGroups = [
      "wheel"
      "video"
      "input"
      "uinput" # asr-rs hold-space PTT: typing-key grab replays through /dev/uinput
      "render"
      "networkmanager"
    ];
    shell = pkgs.fish;
    linger = true;
  };
  programs.fish.enable = true;
  # Key-only mesh: tom has no password (locked account), so password-sudo would leave
  # every headless box with no root path at all. Wheel sudos without a password.
  security.sudo.wheelNeedsPassword = false;

  # --- session: greetd → niri ---
  programs.niri.enable = true;
  services.greetd = {
    enable = true;
    # NB: do NOT wrap these session blocks in lib.mkDefault — greetd's freeform TOML
    # settings replace (not deep-merge) the attrset, and a whole-attrset mkDefault
    # loses the command, producing "default_session contains no command" (jul5).
    settings.default_session = {
      command = "${pkgs.greetd}/bin/agreety --cmd niri-session";
      user = "greeter";
    };
    # Autologin tom → niri at boot on every host (fleet-wide, moved here from the
    # worker's headless-display.nix). tom is a locked/key-only account: passwordless
    # login + passwordless sudo (wheelNeedsPassword=false) means no password is ever
    # prompted. The out-of-store config checkout is guaranteed present before this
    # runs by ./dotfiles-bootstrap.nix (ordered before greetd).
    #
    # NB: there is NO usable interactive fallback — default_session (agreety) prompts
    # for a password tom does not have, so it cannot log him in. Real recovery if this
    # session fails is the VT2-6 getty autologin below (Ctrl+Alt+F2) or a reboot.
    settings.initial_session = {
      command = "${config.programs.niri.package}/bin/niri-session";
      user = "tom";
    };
  };

  # Console recovery: greetd autologins tom→niri on VT1. If the compositor ever fails
  # to start (as on the jul5 duo dual-eDP hang), a locked/key-only account would leave
  # nobody able to log in at the screen. agetty autologin on the other VTs gives tom a
  # guaranteed console shell (Ctrl+Alt+F2). Secret-free and consistent with the fleet's
  # security model — physical access already implies full access (autologin + nopasswd
  # sudo); `login -f` works even though the account is password-locked.
  # (greetd is hardwired to VT1 in this nixpkgs, so getty keeps VT2-6 for recovery.)
  services.getty.autologinUser = lib.mkDefault "tom";

  # asr-rs global push-to-talk on a typing key (hold SPACE): the keyboard is
  # EVIOCGRAB-ed and re-emitted through a /dev/uinput passthrough, which needs
  # the uinput device + group (tom is in it above).
  hardware.uinput.enable = true;

  # --- audio ---
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # --- desktop plumbing ---
  hardware.bluetooth.enable = true;
  services.hardware.bolt.enable = true; # USB4/Thunderbolt authorization (cluster link)
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;
  security.polkit.enable = true;
  programs.dconf.enable = true; # so home-manager dconf theme keys apply
  services.gvfs.enable = true;
  services.udisks2.enable = true;
  services.power-profiles-daemon.enable = true;
  services.fprintd.enable = true; # fingerprint
  services.fwupd.enable = true; # firmware updates
  programs.ydotool.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # --- containers ---
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  # --- networking niceties ---
  services.openssh = {
    enable = true;
    startWhenNeeded = true;
  };
  services.tailscale.enable = true;
  # Tailscale SSH: any mesh node can reach any other over the tailnet in ANY
  # situation (LAN, remote, or when the TB5 fabric is down), authenticated by
  # tailnet identity — no user keypair needed for this path. extraSetFlags runs
  # `tailscale set --ssh` on every activation, so it also enables SSH on nodes
  # already joined to the tailnet (the autoconnect unit only runs `up` while
  # BackendState=NeedsLogin, so extraUpFlags alone would never re-fire).
  # NB: requires an `ssh` rule in the tailnet ACL allowing tag:mesh → tag:mesh
  # for users [autogroup:nonroot, root] — added in the Tailscale admin console.
  services.tailscale.extraSetFlags = [ "--ssh" ];
  services.resolved.enable = true;
  networking.firewall.enable = true;
  # wayvnc (port 5900) is reachable ONLY over the tailnet — never the LAN/wifi. The
  # direct Thunderbolt link is already a trusted interface (see modules/strix.nix).
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 5900 ];

  # --- zram (cap at 8 GiB; bare enable would balloon on the 128 GB boxes) ---
  zramSwap = {
    enable = true;
    memoryMax = 8 * 1024 * 1024 * 1024;
  };

  # --- firmware / graphics base (per-device graphics in host files) ---
  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;

  # --- fonts (the rule: maple-mono + jetbrains nerd + google-fonts + noto-emoji
  #     + the Apple families) ---
  # Apple SF/NY come from the apple-fonts flake overlay: built at nix-build time
  # from Apple's own CDN DMGs, nothing redistributed. sfmono-liga (pkgs/) is the
  # ligaturized+nerd-patched SF Mono. The apple-fonts -nerd variants are skipped
  # on purpose: nerd-font-patcher OOMs constrained builders and sfmono-liga
  # already carries the terminal glyphs.
  fonts.packages = with pkgs; [
    maple-mono.NF
    nerd-fonts.jetbrains-mono
    google-fonts
    noto-fonts-color-emoji
    sf-pro # GTK interface font ("SF Pro Display 11" — dconf in home/home.nix)
    sf-compact
    sf-mono
    ny
    sfmono-liga
  ];

  # Map the fontconfig generic aliases to the Apple families. Installing the
  # fonts (above) is not enough: apps that ask for the *generic* families —
  # google-chrome's web content (sans-serif/serif/monospace), plus most GTK/Qt
  # fallbacks — resolve through these aliases, which otherwise default to
  # DejaVu. That DejaVu fallback is the "weird font" Chrome renders with. The
  # family strings are the real names the DMG-built OTFs expose (verified with
  # fc-scan): "SF Pro Display", "New York", "Liga SFMono Nerd Font" — NOT
  # "SF Mono". NixOS appends its own DejaVu/Noto fallbacks after these, so
  # missing glyphs (CJK, symbols) still resolve.
  fonts.fontconfig.defaultFonts = {
    sansSerif = [
      "SF Pro Display"
      "SF Pro Text"
    ];
    serif = [ "New York" ];
    monospace = [ "Liga SFMono Nerd Font" ];
    emoji = [ "Noto Color Emoji" ];
  };

  # --- env (qt + gtk theming) ---
  environment.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "qt6ct";
    # GTK reads GTK_THEME with the highest priority. niri has no XSettings/settings
    # daemon, so this system-wide export (reaching GUI apps via the PAM session) is
    # what makes GTK3 apps like Remmina honor the theme without nwg-look. It must be
    # here, not home.sessionVariables (which only reaches interactive shells).
    GTK_THEME = "MacTahoe-Dark-grey";
    # Chromium/Electron (google-chrome + PWA launchers) only run native Wayland
    # under niri with this set; otherwise they fall back to X11 and blur/fail.
    NIXOS_OZONE_WL = "1";
  };

  # --- base system packages (the rest are user packages in home/) ---
  environment.systemPackages = with pkgs; [
    git
    vim
    wl-clipboard
    age
    # sox provides `rec`/`play` — Claude Code's /voice records through sox on
    # Linux; without it voice input fails ("check your microphone").
    sox
    # attic client — `attic login`/`attic push` against the fleet cache (#42).
    # Present fleet-wide so any host can pull-login and the designated builder
    # (worker) can push built closures. Server pkg is pulled by hosts/coordinator.
    attic-client
  ];

  system.stateVersion = "26.05";
}
