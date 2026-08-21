{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# zenbook-duo — Intel Asus Zenbook Duo UX8406 (dual-screen). The FIRST flash target.
# No dedicated nixos-hardware module → compose generics. Second display + IPU6 webcam +
# the titdb touchpad bits are follow-ups (niri / out-of-nixpkgs). The old
# "zenbook-duo-daemon" slot is now filled by ntm (mecattaf/ntm, home/ntm.nix): bezel
# gestures + accelerometer rotation, fed by hardware.sensor.iio below.
{
  imports = [
    ./hardware.nix
    ./disko.nix
    inputs.nixos-hardware.nixosModules.common-cpu-intel
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
    # AdGuard REMOVED 2026-08-21 (audit finding: live landmine). Same DoH
    # collision as the coordinator's removal that day: the loopback
    # instance's upstreams (1.1.1.1/1.0.0.1/9.9.9.9:443) are exactly what
    # the NAS dns_hijack drops, so this laptop's DNS would go dark the
    # moment it joined the home LAN. On thomas-6ghz it gets the NAS
    # resolver (filtered); on foreign networks it uses their DHCP DNS,
    # unfiltered — the roaming trade, accepted.
  ];

  networking.hostName = "zenbook-duo";

  # agenix secret delivery ON — same post-flash two-step used by the coordinator
  # (the delivered /etc/ssh/ssh_host_ed25519_key matches mesh-registry.nix, so agenix
  # decrypts against it). Delivers the shared tom@mesh SSH key for fleet access.
  mySecrets.enable = true;

  # thomas-6ghz — the home LAN's fleet band (2026-08-21 "6ghz fleet wide"
  # ruling). Same shape as the coordinator's profile in
  # hosts/coordinator/uplink-nas.nix: SSID/PSK substituted from wifi-lan.age
  # (this host joined the recipients that day), WPA3-SAE + PMF as 6GHz
  # mandates, no BSSID pin (single-radio SSID — no roam surface; and this
  # Intel AX211 laptop never had the mt7925 crash class anyway), and no
  # interface-name so the profile survives an iface rename. DHCP on
  # purpose: a roaming laptop takes a pool lease (.10-.200), unlike the
  # coordinator's load-bearing static .2. Priority sits above any imperative
  # foreign-network profiles so home always wins when in range.
  networking.networkmanager.ensureProfiles.environmentFiles =
    lib.optional (builtins.pathExists ../../secrets/wifi-lan.age) config.age.secrets.wifi-lan.path;
  networking.networkmanager.ensureProfiles.profiles.thomas-6ghz =
    lib.mkIf (builtins.pathExists ../../secrets/wifi-lan.age) {
      connection = {
        id = "thomas-6ghz";
        type = "wifi";
        autoconnect = true;
        autoconnect-priority = 110;
      };
      wifi = {
        mode = "infrastructure";
        ssid = "$BE550_SSID";
      };
      wifi-security = {
        key-mgmt = "sae";
        pmf = 3;
        psk = "$BE550_PSK";
      };
      ipv4.method = "auto";
      ipv6.method = "ignore";
    };

  boot.kernelParams = [ "i915.enable_psr=0" ]; # eDP PSR flicker

  # jul5 dual-eDP niri startup hang mitigation (NEEDS LIVE VERIFY): niri.service is
  # Type=notify and was SIGKILLed at systemd's 90s default before signalling ready.
  # Give it rope so a *slow* (vs deadlocked) start survives and can be diagnosed from
  # the journal. This is a diagnostic aid, not a proven fix — pair with the early i915
  # KMS in hardware.nix and check `journalctl --user -u niri -b` on next boot.
  systemd.user.services.niri.serviceConfig.TimeoutStartSec = lib.mkForce "120";

  # Dual-touchscreen: this host ALONE runs the PR #1856 niri (per-device touch →
  # output mapping); the coordinator stays on stock `pkgs.niri`. The fork build
  # is a lazy overlay attr, so only this override triggers it. Per-device blocks
  # ship via ~/.config/niri-local.kdl (home.nix, host-gated). See overlays/default.nix
  # and dotfiles#67. Drop this line + the niri-local blocks once #1856 lands upstream.
  programs.niri.package = pkgs.niri-pr1856;

  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  # ntm rotation feed: iio-sensor-proxy on the system bus (net.hadess.SensorProxy).
  # NB: NixOS spells this hardware.sensor.iio, not services.iio-sensor-proxy (the
  # option ntm's README suggests). The ntm daemon itself is home-side: home/ntm.nix.
  hardware.sensor.iio.enable = true;

  services.asusd.enable = true; # kbd backlight, charge-limit, platform-profile
  services.thermald.enable = true; # Intel thermal throttling protection (decided: Intel-only)
}
