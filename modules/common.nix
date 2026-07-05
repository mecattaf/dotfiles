{ pkgs, lib, ... }:
# Device-agnostic layer — every host imports this. Use lib.mkDefault for
# anything a host or nixos-hardware module may override.
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

  # --- session: greetd → niri ---
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
