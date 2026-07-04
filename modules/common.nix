{ pkgs, lib, ... }:
# Device-agnostic layer — every host imports this. No custom option namespace here.
# Reflects nix-decisions.md. RAW configs / home-manager live in home/home.nix.
# Use lib.mkDefault for anything a host or nixos-hardware module may override.
{
  # --- identity / base ---
  networking.networkmanager.enable = true;
  time.timeZone = lib.mkDefault "America/New_York";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
  system.nixos.distroName = "Harness";
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
  boot.plymouth.enable = true; # boot splash — decided: keep
  # Issue #33: shpool session leak exhausted the default 128 inotify instances.
  # Bump ports the headroom; the session-naming fix itself is tracked in notes
  # (dotfiles-pass / remote-terminal capture).
  boot.kernel.sysctl."fs.inotify.max_user_instances" = 512;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };

  # --- user ---
  users.users.tom = {
    isNormalUser = true;
    description = "tom";
    extraGroups = [
      "wheel"
      "video"
      "input"
      "render"
      "networkmanager"
    ];
    shell = pkgs.fish;
    linger = true;
  };
  programs.fish.enable = true;

  # --- session: greetd → niri (RAW config via home-manager; niri-flake comes later) ---
  programs.niri.enable = true;
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.greetd}/bin/agreety --cmd niri-session";
      user = "greeter";
    };
  };

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
  services.gvfs.enable = true;
  services.udisks2.enable = true;
  services.power-profiles-daemon.enable = true;
  services.fprintd.enable = true; # fingerprint — decided: all devices
  services.fwupd.enable = true; # firmware updates — decided: keep
  programs.ydotool.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # --- containers (quadlets land on the coordinator later) ---
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
  services.resolved.enable = true;
  networking.firewall.enable = true;

  # --- zram (cap at 8 GiB; bare enable would balloon on the 128 GB boxes) ---
  zramSwap = {
    enable = true;
    memoryMax = 8 * 1024 * 1024 * 1024;
  };

  # --- firmware / graphics base (per-device graphics in host files) ---
  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;

  # --- fonts (the rule: maple-mono + jetbrains nerd + google-fonts + noto-emoji) ---
  fonts.packages = with pkgs; [
    maple-mono.NF
    nerd-fonts.jetbrains-mono
    google-fonts
    noto-fonts-color-emoji
  ];

  # --- env (qt theming; bar-less / notification-less by decision) ---
  environment.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "qt6ct";
    # Chromium/Electron (google-chrome + the 11 PWA launchers) run native Wayland on
    # NixOS only with this set; without it they fall back to X11 and fail/blur under
    # niri (audit: "no NIXOS_OZONE_WL, no xwayland-satellite").
    NIXOS_OZONE_WL = "1";
  };

  # --- base system packages (the rest are user packages in home/) ---
  environment.systemPackages = with pkgs; [
    git
    vim
    wl-clipboard
    age # secrets tooling kept; sops itself is a later session
  ];

  # GONE by decision: flatpak, YubiKey/pcscd, fcitx5/ibus, bar/notification daemon,
  # just/hjust/gum, ramalama, valent, iio-niri, VM guest agents.
  #
  # DEFERRED — genuinely outstanding ONLY (issue #35 pruned the already-landed items:
  # codecs, pythonForNiri, nautilus set, shpool, the SAME-bucket apps, gh/gcloud —
  # all live in home/home.nix now):
  #   - agent stack MODULES: pi.nix + llm-agents.nix flake inputs (binaries gh/gcloud landed)
  #   Coordinator-only: cockpit, cloudflared tunnel service, cifs-utils+NAS mount,
  #   cups/NM-VPN, quadlets.

  system.stateVersion = "26.05"; # current stable line (fresh install, honest value)
}
