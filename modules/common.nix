{ pkgs, lib, config, ... }:
# Device-agnostic layer — every host imports this. Use lib.mkDefault for
# anything a host or nixos-hardware module may override.
let
  # See services.greetd.settings.initial_session below. On a fresh flash, tom's
  # out-of-store config symlinks dangle until the dotfiles checkout exists; this
  # wrapper clones the PUBLIC repo (best-effort, bounded) then execs the real
  # niri-session, so first boot comes up with the real config and zero manual steps.
  ensureDotfilesSession = pkgs.writeShellScript "niri-session-ensure-dotfiles" ''
    set -u
    repo="$HOME/mecattaf/dotfiles"
    if [ ! -e "$repo/home/dot_config/niri/config.kdl" ]; then
      echo "ensure-dotfiles: checkout missing at $repo — cloning github.com/mecattaf/dotfiles" >&2
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$repo")"
      ${pkgs.coreutils}/bin/timeout 180 ${pkgs.git}/bin/git clone \
        https://github.com/mecattaf/dotfiles.git "$repo" \
        || echo "ensure-dotfiles: clone failed (offline?) — niri will use default config" >&2
    fi
    exec ${config.programs.niri.package}/bin/niri-session
  '';
in
{
  imports = [
    ./mesh.nix # SSH mesh trust (known_hosts + authorized_keys)
    ./secrets.nix # agenix secret delivery (gated by mySecrets.enable, default off)
  ];

  # --- identity / base ---
  networking.networkmanager.enable = true;
  time.timeZone = lib.mkDefault "America/New_York";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
  system.nixos.distroName = "Harness";
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
  boot.plymouth.enable = true;
  # shpool sessions exhaust the default 128 inotify instances; raise the ceiling.
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
  # Key-only mesh: tom has no password (locked account), so password-sudo would leave
  # every headless box with no root path at all. Wheel sudos without a password.
  security.sudo.wheelNeedsPassword = false;

  # --- session: greetd → niri ---
  programs.niri.enable = true;
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.greetd}/bin/agreety --cmd niri-session";
      user = "greeter";
    };
    # Autologin tom → niri at boot on every host (fleet-wide, moved here from the
    # worker's headless-display.nix). tom is a locked/key-only account: passwordless
    # login + passwordless sudo (wheelNeedsPassword=false) means no password is ever
    # prompted. Subsequent logins after logout fall back to default_session (agreety).
    #
    # The session command is NOT bare niri-session: home-manager deploys tom's
    # ~/.config/* (niri, kitty, fish, kanshi, ~/.local/bin) as OUT-OF-STORE symlinks
    # into ${repoDir} (see home/home.nix `mkOutOfStoreSymlink`). On a freshly-flashed
    # box that checkout does not exist yet, so every config would dangle and niri would
    # boot with defaults (this bit the jul5 duo flash). ensure-dotfiles clones the
    # PUBLIC repo (best-effort, bounded) before handing off to niri, so a fresh flash
    # comes up with the real config with zero manual steps. Idempotent: instant once
    # the checkout is present (e.g. the operator's primary box, or any 2nd boot).
    settings.initial_session = {
      command = "${ensureDotfilesSession}";
      user = "tom";
    };
  };

  # Console recovery: greetd autologins tom→niri on VT1. If the compositor ever fails
  # to start (as on the jul5 duo dual-eDP hang), a locked/key-only account would leave
  # nobody able to log in at the screen. agetty autologin on the other VTs gives tom a
  # guaranteed console shell (Ctrl+Alt+F2). Secret-free and consistent with the fleet's
  # security model — physical access already implies full access (autologin + nopasswd
  # sudo); `login -f` works even though the account is password-locked.
  services.getty.autologinUser = lib.mkDefault "tom";

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

  # --- fonts (the rule: maple-mono + jetbrains nerd + google-fonts + noto-emoji) ---
  fonts.packages = with pkgs; [
    maple-mono.NF
    nerd-fonts.jetbrains-mono
    google-fonts
    noto-fonts-color-emoji
  ];

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
  ];

  system.stateVersion = "26.05";
}
