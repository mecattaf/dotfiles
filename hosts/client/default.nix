{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# client — the ASUS Zenbook Duo UX8406MA (Meteor Lake, two 2880x1800 eDP
# panels, detachable keyboard), Tom's main input device since 2026-09-11.
#
# The machine's third life in this house: `zenbook-duo` in this tree from the
# jul5 flash to 2026-08-30 (removed in 77eac406/22eebdc0), then Marwan's
# Omarchy laptop in omarchy-fleet for three days, then reclaimed the same
# afternoon it was ready — "i want to see my omarchy-less asus zenbook ready
# for action asap now". The return is an IN-PLACE SWITCH onto the fleet's
# install, not a reflash: the disk layout (./disko.nix), the ssh host key
# (modules/mesh-registry.nix — reused, never minted), /var/lib/tailscale* and
# the NetworkManager profiles all stay, and the Omarchy generation stays in
# the boot menu as the rollback.
#
# WHAT IT IS, in one line: a thin client. It shows Tom niri, kitty, Chrome and
# the dock's peripherals, and everything that thinks runs on the coordinator
# (herdr server, the Claude/Codex/pi seats, tally, the artifact and microVM
# planes) or the worker (Halogen). Mod+Return on this box is a herdr window
# INTO the coordinator (`hk ssh --in-place coordinator`, home/home.nix's
# niri-local.kdl branch); `desk` is the fish spelling of the same thing.
#
# WHAT IT IS NOT:
#   * not an agent host — no herdr server (home/herdr.nix is coordinator-
#     gated), no Claude/Codex credential (secrets.nix: coordinatorOnly, the
#     jul12 "own session" ruling stands), no tally clocks, no voxtype, no
#     transcript mirror, no dcal daemon, no paper timers. Every one of those
#     is `hostName == "coordinator"`-gated in home/; the flake's home-profiles
#     check asserts their absence here.
#   * not a server of anything — no wayvnc (home/remote.nix is coordinator-
#     gated since this host exists; it gets the Remmina client and the
#     `coordinator (VNC)` profile), no atuin server, no caddy, no immich or
#     navidrome relay, no journal upload to the NAS (hosts/nas/journal.nix
#     admits the twins only), no printing queue (forced off below), no
#     microVM host, no model tooling.
#   * not a twin — modules/fleet-hosts.nix and modules/strix.nix are not
#     imported; the two LAN names it dials are pinned below instead, and the
#     stock 127.0.0.2 self-mapping stays because nothing here binds by
#     hostname.
#   * not a roaming node yet — tailscaled is declared (so the daemon exists
#     and a later `tailscale up --login-server=…` against the NAS headscale
#     re-uses the state on disk) but there is no auth key, no autoconnect
#     unit and no `up` in any activation. On the LAN there is nothing but
#     the LAN. See the tailscale block below.
#   * not pushed to — like every device it pulls: the NAS builds this
#     closure nightly (hosts/nas/update-center.nix) once that box is
#     switched; activation is Tom, docked, running
#       sudo nixos-rebuild switch --flake github:mecattaf/dotfiles/main#client
#     Coordinator first whenever herdr is bumped (the two speak a versioned
#     protocol and the laptop projects the coordinator's server).
#
# The hardware layer below is omarchy-fleet's profiles/zenbook-duo.nix +
# hosts/zenbook-duo/hardware.nix merged with 77eac406^'s host module; each
# omission is recorded where it would have gone.
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ./audio.nix # pins the iContact webcam mic (on the dock) as the default source
    ./lid.nix # the lid does nothing to logind; niri (per-host slot) owns the backlight half
    # No dedicated nixos-hardware module for the UX8406; compose the generics.
    # common-pc-laptop does NOT enable bolt — modules/common.nix does, fleet-
    # wide, and this docking host is exactly what that line is for.
    inputs.nixos-hardware.nixosModules.common-cpu-intel
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
    ../../modules/zenbook-duo-daemon.nix
  ];

  networking.hostName = "client";

  # agenix delivery ON. The host key on the box IS the 2026-09-07 fleet key
  # (read live 2026-09-11, equals the registry row), so the delivered tier
  # re-minted for this host in the same commit decrypts on the first boot of
  # this closure — no flash, no host-key dance. Same pattern as the worker's
  # 2026-08-21 return.
  mySecrets.enable = true;

  # ── names ──────────────────────────────────────────────────────────────────
  # `nas` is fleet-wide (modules/common.nix). The two twins are pinned here
  # by hand because modules/fleet-hosts.nix is twins-only and also deletes
  # the 127.0.0.2 self-mapping, which this box has no reason to lose. The
  # NAS resolver does not serve DHCP client names (checked 2026-09-11:
  # `resolvectl query zenbook-duo` → not found while the box held a lease),
  # so a laptop that dials `coordinator` needs its own answer. One answer per
  # name per host, registry aliases both, so ssh stays TOFU-free.
  networking.hosts."10.42.0.2" = [ "coordinator" ];
  networking.hosts."10.42.0.5" = [ "worker" ];

  # ── the LAN identity: thomas-6ghz, DHCP ────────────────────────────────────
  # Same profile the box already associates with (the fleet delivered one by
  # hand on 2026-09-07; this is its declarative twin, SSID/PSK from
  # wifi-lan.age, WPA3-SAE + PMF as 6 GHz mandates, no BSSID pin — single-
  # radio SSID — and no interface-name so an iface rename survives). DHCP on
  # purpose: the NAS hands this MAC (a0:b3:39:06:75:a7) 10.42.0.16, and
  # hosts/nas/router.nix pins that lease so the registry alias and the twins'
  # /etc/hosts line for `client` stay true across renewals.
  #
  # ⚠ ensureProfiles never deletes: the hand-delivered thomas-6ghz keyfile in
  # /etc/NetworkManager/system-connections/ survives the switch beside this
  # one until an operator removes it (DECISIONS.md, 2026-09-11).
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
  # Same INFO reasoning as the twins: wifi incidents on this fleet were once
  # forensically blind because NetworkManager logged nothing for weeks.
  networking.networkmanager.logLevel = "INFO";

  # ── tailnet: declared, dormant ─────────────────────────────────────────────
  # Tom's ruling 2026-09-11: on the LAN, nothing but the LAN. The daemon is
  # enabled so the node state omarchy-fleet left under /var/lib/tailscale is
  # kept and so a later, MANUAL
  #   sudo tailscale up --login-server=https://nas-saas.tail8dd1.ts.net:8443
  # joins the NAS headscale (the fleet rail's control URL, from omarchy-fleet
  # modules/fleet-rail.nix) — never tailscale.com: the SaaS `zenbook-duo` node
  # was removed on 2026-09-10 with "will never touch this again". No
  # secrets/tailscale-authkey-client.age exists, so modules/secrets.nix wires
  # no authKeyFile and no autoconnect unit; extraUpFlags only records the
  # control plane a future key would go to. The fleet's own rail (a second,
  # userspace tailscaled with state in /var/lib/tailscale-fleet, headscale
  # node 4 `zenbook-duo-fleet`) is not declared here; its state dir is left in
  # place for the operator to reuse or delete. Kernel-mode tailscaled (the
  # NixOS default; the fleet rail was userspace with --accept-routes=false),
  # so a future NAS subnet route for 10.42.0.0/24 can actually be used.
  services.tailscale.enable = true;
  services.tailscale.extraUpFlags = [ "--login-server=https://nas-saas.tail8dd1.ts.net:8443" ];

  # ── the Thunderbolt 3 dock ─────────────────────────────────────────────────
  # This is the docking host: the coordinator's webcam/mic, Sound Blaster,
  # INZONE dongle, Glove80 and Magic Trackpad all hang off a TB3 dock on this
  # laptop's Type-C port. boltd authorizes the dock; the domain reports
  # security "iommu+user", so a plugged dock may still need one enrolment
  # (`boltctl list`, then `boltctl enroll --policy auto <uuid>` once).
  # The fleet-wide bolt line left modules/common.nix on 2026-09-11 with the
  # twins' Thunderbolt ban (DECISIONS.md, the "later the same day" entry):
  # that ban is about the two Strix boxes never using the bus between
  # themselves again, and does not reach a laptop whose whole peripheral
  # plane sits behind a dock. Declared here, host-scoped, on purpose.
  services.hardware.bolt.enable = true;
  # lsusb for dock inspection over ssh; the coordinator has it, this box
  # otherwise would not.
  environment.systemPackages = [ pkgs.usbutils ];

  # ── no printing queue on a thin client ─────────────────────────────────────
  # modules/printing.nix is fleet-wide for interactive hosts; printing from
  # here goes through a Chrome tab on the coordinator or the print skill
  # there. Off, and its ensure-printers unit masked so the module's drop-in
  # cannot leave a half-defined service behind.
  services.printing.enable = lib.mkForce false;
  systemd.services.ensure-printers.enable = false;

  # ── panels, PSR, video ─────────────────────────────────────────────────────
  # i915 is the bound driver (xe loaded but idle); eDP PSR flicker.
  boot.kernelParams = [ "i915.enable_psr=0" ];
  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  # jul5 dual-eDP niri startup hang mitigation, NEVER live-verified: niri.service
  # is Type=notify and was SIGKILLed at systemd's 90 s default before signalling
  # ready. Rope for a slow (vs deadlocked) start; harmless if unneeded.
  systemd.user.services.niri.serviceConfig.TimeoutStartSec = lib.mkForce "120";

  # The dock contract (modules/zenbook-duo-daemon.nix): keyboard on → eDP-2
  # off, backlights synced, Fn keys. kanshi's `Duo` profile covers both panels
  # lit; with the keyboard docked only eDP-1 remains and kanshi applies
  # `DuoDocked` (home/dot_config/kanshi/config, one of the Duo's four profiles
  # M-5 wrote — the Dell-era `Laptop` profile is gone).
  services.zenbook-duo-daemon.enable = true;

  # ── the Duo's own quirks, all measured on this metal by omarchy-fleet ──────
  # No RTC cell: a fully drained battery resets the clock to 2024. e2fsck then
  # refused root ("last write time in the future") and the initrd sat in
  # emergency mode with no shell. Two defences: e2fsck ignores the clock, and
  # the initrd offers a shell. timesyncd repairs the date once online.
  environment.etc."e2fsck.conf".text = "[options]\nbroken_system_clock = 1\n";
  boot.initrd.systemd.contents."/etc/e2fsck.conf".text = "[options]\nbroken_system_clock = 1\n";
  boot.initrd.systemd.emergencyAccess = true;
  services.timesyncd.enable = true;

  # asusd for charge-limit / platform-profile (never set; threshold reads 100).
  # Its upstream unit sandboxes onto /etc/asusd and nothing creates that dir,
  # so without the tmpfiles line it dies status=226/NAMESPACE before exec and
  # burns its five restarts in a second (omarchy-fleet R37).
  services.asusd.enable = true;
  systemd.tmpfiles.rules = [ "d /etc/asusd 0755 root root -" ];
  services.thermald.enable = true;

  # The asus_screenpad backlight reports brightness 130816 against a max of
  # 255, so systemd-backlight's save/restore fails on every boot. Mask the
  # instance (suppressedSystemUnits proved insufficient — udev re-instantiates
  # the template); the daemon owns that panel's brightness, and
  # home/dot_local/bin/brightness only touches DRM backlights anyway.
  systemd.services."systemd-backlight@backlight:asus_screenpad".enable = false;

  # No swap partition → no hibernate; power off at the threshold instead.
  services.upower = {
    enable = true;
    percentageAction = 5;
    criticalPowerAction = "PowerOff";
  };

  # iio-sensor-proxy on the system bus. Cheap, and its only consumer —
  # rotation — is deferred (the fleet's rotate module was Hyprland-only, ntm
  # never auto-started).
  hardware.sensor.iio.enable = true;
}
