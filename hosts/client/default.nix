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
# WHAT IT IS, in one line: a thin client. It shows Tom Sway, kitty, Chrome and
# the dock's peripherals. Herdr and the Claude/Codex/dsh sessions run on NAS;
# builds and model inference run on the Strix compute pair. Mod+Return is a
# herdr window INTO NAS (~/.local/bin/herdr-projector, `herdr --remote
# nas`, driven by herdr-chord from sway/binds.conf, #385); `desk` is the fish
# spelling of the same thing.
#
# WHAT IT IS NOT:
#   * not an agent host — no herdr server (home/herdr.nix is brain-
#     gated), no Claude/Codex credential (secrets.nix: brainOnly, the
#     jul12 "own session" ruling stands), no tally clocks, no voxtype, no
#     transcript mirror, no paper timers. Every one of those
#     is brain-role-gated in home/; the flake's home-profiles
#     check asserts their absence here.
#   * not a runner of anything, with ONE exception — ./huion.nix pulls the
#     Huion Note X10's pages over Bluetooth on connect and pushes them to
#     strix:~/Paper/inbox (one udev-triggered oneshot, one retry
#     timer, a patched bluetoothd), because the radio is here
#     (DECISIONS.md, 2026-09-13). Nothing else is added to this box for it.
#   * not a server of anything — no wayvnc (no VNC in the fleet since the
#     2026-09-11 headless flip: home/remote.nix and its Remmina viewer
#     profile went with the strix's session), no atuin server, no
#     caddy, no immich or
#     navidrome relay, no journal upload to the NAS (hosts/nas/journal.nix
#     admits the twins only), no printing queue (forced off below), no
#     microVM host, no model tooling.
#   * not a twin — modules/fleet-hosts.nix and modules/strix.nix are not
#     imported; the two LAN names it dials are pinned below instead, and the
#     stock 127.0.0.2 self-mapping stays because nothing here binds by
#     hostname.
#   * official tailscale.com membership: NAS exit node and subnet router,
#     with direct LAN access retained. Enrollment and non-expiring node keys
#     use the admin-console procedure in docs/nas-agent-transport.md.
#   * not a builder: updates are evaluated and built on the strix and pushed
#     (Tom, 2026-10-11: "can't that be done on the strix side of things?
#     since it's a much more powerful device"). From the strix:
#       deploy github:mecattaf/dotfiles/<rev>#client   (deploy.nodes.client)
#     A local `sudo nixos-rebuild switch --flake github:mecattaf/dotfiles/main#client`
#     still works but evaluates and builds here, which ran one core at
#     101 C and the fan at 3400 rpm on 2026-10-11.
#     Strix first whenever herdr is bumped (the two speak a versioned
#     protocol and the laptop projects the strix's server).
#
# The hardware layer below is omarchy-fleet's profiles/zenbook-duo.nix +
# hosts/zenbook-duo/hardware.nix merged with 77eac406^'s host module; each
# omission is recorded where it would have gone.
{
  # Sway + Vicinae desktop (myDisplay.enable defaults to true); hardware
  # stays host-specific.

  imports = [
    ../../modules/local-models.nix
    ./hardware.nix
    ./disko.nix
    ./audio.nix # pins the iContact webcam mic (on the dock) as the default source
    ./lid.nix # the lid does nothing to logind; Sway (sway-local.conf) owns the backlight half
    ./strix-reachability.nix
    ./trackpad.nix
    ./huion.nix # the Huion Note X10 paper inbox: patched bluetoothd, hid-generic unbind
    ./wifi-ladder.nix # thomas-6ghz -> thomas-6ghz-direct -> Freebox and back (Tom, 2026-10-25)
    # No dedicated nixos-hardware module for the UX8406; compose the generics.
    # common-pc-laptop does NOT enable bolt — modules/common.nix does, fleet-
    # wide, and this docking host is exactly what that line is for.
    inputs.nixos-hardware.nixosModules.common-cpu-intel
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
    ../../modules/zenbook-duo-daemon.nix
    ../../modules/keyring-autounlock.nix # TPM-sealed keyring unlock; greetd autologin types no password
  ];

  networking.hostName = "client";
  myFleet.roles = [ "seat" ];

  # No dotfiles checkout on the thin client (Tom, 2026-10-11, about ~/dotfiles
  # and ~/mecattaf here: "i dnt need here"). Every raw dotfile (sway, kitty,
  # fish, ~/.local/bin, herdr's config.toml, nvim) comes from the Nix store,
  # so a deploy from the strix carries both halves at one rev and nothing has
  # to be pulled here afterwards. This also turns off raw-dotfiles-guard and
  # modules/dotfiles-bootstrap.nix on this host (home/raw-dotfiles-guard.nix).
  home-manager.users.tom.rawDotfiles.inStore = true;

  # agenix delivery ON. The host key on the box IS the 2026-09-07 fleet key
  # (read live 2026-09-11, equals the registry row), so the delivered tier
  # re-minted for this host in the same commit decrypts on the first boot of
  # this closure — no flash, no host-key dance. Same pattern as the worker's
  # 2026-08-21 return.
  mySecrets.enable = true;

  # Fleet names come from modules/fleet-hosts.nix, including the LAN peers.

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
  networking.networkmanager.ensureProfiles.environmentFiles = lib.optional (builtins.pathExists ../../secrets/wifi-lan.age) config.age.secrets.wifi-lan.path;
  networking.networkmanager.ensureProfiles.profiles.thomas-6ghz =
    lib.mkIf (builtins.pathExists ../../secrets/wifi-lan.age)
      {
        connection = {
          id = "thomas-6ghz";
          type = "wifi";
          autoconnect = true;
          autoconnect-priority = 110;
          # Rung 1 of ./wifi-ladder.nix: two attempts, then autoconnect reaches
          # thomas-6ghz-direct (priority 100) when the NAS hands out no lease.
          autoconnect-retries = 2;
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
        ipv4.dhcp-timeout = 20; # dnsmasq answers in milliseconds; the 45 s default only delays the fallback
        ipv4.may-fail = false; # IPv6 is ignored, so a missing lease must fail the activation
        # Prefer the direct home LAN over accepted Tailscale subnet routes.
        # NetworkManager removes this rule when this Wi-Fi profile goes down,
        # so roaming still uses the NAS subnet route without manual toggles.
        ipv4.routing-rule1 = "priority 2500 to 10.42.0.0/24 table 254";
        ipv6.method = "ignore";
      };
  # Same INFO reasoning as the twins: wifi incidents on this fleet were once
  # forensically blind because NetworkManager logged nothing for weeks.
  networking.networkmanager.logLevel = "INFO";

  # wpa_supplicant (NetworkManager's backend) is pulled in by multi-user.target
  # in the same instant iwlwifi registers wlan0, and the wpa_supplicant
  # module's udev rule `try-restart`s it on that add event. When the restart
  # lands in the unit's ExecStartPre chmod/chown, the SIGTERM marks the unit
  # failed and surfaces an episode, although it comes straight back up (three
  # of six boots, 2026-10-07..10). Start it once udev has finished with the
  # card, so the restart finds nothing running. A missing card costs the
  # device timeout, not a failure.
  systemd.services.wpa_supplicant = {
    wants = [ "sys-subsystem-net-devices-wlo1.device" ];
    after = [ "sys-subsystem-net-devices-wlo1.device" ];
  };

  # Ordinary Tailscale for roaming access through the NAS subnet router.
  # Enrollment is interactive; no auth key is embedded or re-applied at boot.
  # modules/fleet-transport.nix owns the shared preferences.

  # ── failure surfacing: tom is uid 1001 here ────────────────────────────────
  # modules/failure-surfacing.nix watches the user manager of uid 1000 by
  # default, which is tom on the twins. On this box tom is 1001 (the Omarchy
  # install's uid ordering, kept by the in-place switch), so the default made
  # failure-marker-reconcile spawn a `systemctl --user --machine=1000@.host`
  # bridge that died with "Unknown user 1000" on every tick — a failed
  # transient unit surfaced as its own episode — and left this user manager's
  # unit failures unwatched. Name the real uid.
  myFailureSurfacing.userManagerUids = [ 1001 ];
  # The same uid for the keyring unlock's user manager.
  myKeyringAutounlock.uid = 1001;

  # ── the Thunderbolt 3 dock ─────────────────────────────────────────────────
  # This is the docking host: the strix's webcam/mic, Sound Blaster,
  # INZONE dongle and Glove80 all hang off a TB3 dock on this laptop's Type-C
  # port. The Magic Trackpad left the dock on 2026-09-17 and is Bluetooth-bonded
  # to the strix alone (hosts/strix/trackpad.nix). boltd authorizes the dock; the domain reports
  # security "iommu+user", so a plugged dock may still need one enrolment
  # (`boltctl list`, then `boltctl enroll --policy auto <uuid>` once).
  # The fleet-wide bolt line left modules/common.nix on 2026-09-11 with the
  # twins' Thunderbolt ban (DECISIONS.md, the "later the same day" entry):
  # that ban is about the two Strix boxes never using the bus between
  # themselves again, and does not reach a laptop whose whole peripheral
  # plane sits behind a dock. Declared here, host-scoped, on purpose.
  services.hardware.bolt.enable = true;
  # lsusb for dock inspection over ssh; the strix has it, this box
  # otherwise would not.
  environment.systemPackages = [ pkgs.usbutils ];

  # ── no printing queue on a thin client ─────────────────────────────────────
  # modules/printing.nix is fleet-wide for interactive hosts; printing from
  # here goes through a Chrome tab on the strix or the print skill
  # there. Off, and its ensure-printers unit masked so the module's drop-in
  # cannot leave a half-defined service behind.
  services.printing.enable = lib.mkForce false;
  systemd.services.ensure-printers.enable = false;

  # ── panels, PSR, video ─────────────────────────────────────────────────────
  # i915 is the bound driver (xe loaded but idle); eDP PSR flicker.
  # nvme_core.default_ps_max_latency_us=0: APST off on the WD PC SN560. Its
  # kernel log carries "nvme … timeout, completion polled" (10 and 11 in two
  # earlier boots, one on 2026-09-14 that stalled the compositor past its start limit),
  # the lost-interrupt signature of a drive failing to leave a deep power
  # state. The cost is idle power on a machine that lives on its dock.
  boot.kernelParams = [
    "i915.enable_psr=0"
    "nvme_core.default_ps_max_latency_us=0"
  ];
  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  # Chrome on this box: VA-API hardware encode for Meet's outgoing camera.
  # Decode is already hardware by default (2026-10-11, measured in a throwaway
  # profile: AV1/VP9 playback on the video engine at ~5% of one core, WebRTC
  # decoder "VaapiVideoDecoder"). Encode was libvpx in software (VP9 1280x720
  # camera loopback 26.7% of one core); with AcceleratedVideoEncoder it is
  # "VaapiVideoEncodeAccelerator" at 14.8%. VP8 stays software: Meteor Lake
  # has no VP8 encoder. WaylandWindowDecorations is repeated because the
  # wrapper's own NIXOS_OZONE_WL --enable-features comes earlier on the line.
  # mkAfter: the override must wrap the nixpkgs-fresh google-chrome that the
  # flake's overlay list installs, not be replaced by it.
  nixpkgs.overlays = lib.mkAfter [
    (_final: prev: {
      google-chrome = prev.google-chrome.override {
        commandLineArgs = "--enable-features=WaylandWindowDecorations,AcceleratedVideoEncoder";
      };
    })
  ];

  # Linux 7.3 like the rest of the fleet (Tom, 2026-10-23), sourced exactly as
  # modules/strix.nix and hosts/nas/kernel.nix do: the versioned attr moves only
  # within 7.3.x and breaks eval loudly when the series ages out.
  boot.kernelPackages =
    (import inputs.nixpkgs-fresh {
      inherit (pkgs.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    }).linuxPackages_7_3;

  # A short boot menu: five generations is rollback enough on a thin client
  # (the 20-entry fleet default left 19 stale entries here, 2026-09-14).
  boot.loader.systemd-boot.configurationLimit = 5;

  # Both panels come up at full brightness on every boot (Tom, 2026-09-14:
  # the saved level was 4/400 and the seat woke nearly black). systemd-backlight
  # would restore whatever was saved at shutdown, so its two DRM instances are
  # off, and udev sets each panel to its own max_brightness as it appears.
  # The Duo keyboard's brightness keys (bin/brightness, 10% steps) adjust from there.
  systemd.services."systemd-backlight@backlight:intel_backlight".enable = false;
  systemd.services."systemd-backlight@backlight:card1-eDP-2-backlight".enable = false;
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="backlight", KERNEL=="intel_backlight|card1-eDP-2-backlight", RUN+="${pkgs.bash}/bin/sh -c 'cat /sys/class/backlight/%k/max_brightness > /sys/class/backlight/%k/brightness'"
    # touchpad-toggle lights the Caps LED while the touchpad is off; let the
    # seat user (group video) write it without a logind round trip.
    ACTION=="add", SUBSYSTEM=="leds", KERNEL=="*::capslock", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/leds/%k/brightness", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/leds/%k/brightness"
  '';

  # The dock contract (modules/zenbook-duo-daemon.nix): keyboard on → eDP-2
  # off, backlights synced, Fn keys. kanshi's `Duo` profile covers both panels
  # lit; with the keyboard docked only eDP-1 remains and kanshi applies
  # `DuoDocked` (home/dot_config/kanshi/config, one of the Duo's two profiles
  # — the dock-monitor ones went on 2026-09-13, see that file's header).
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

  # asusd for charge-limit / platform-profile. The charge limit is set below
  # (battery-charge-limit, 60%); asusd noticed the external write and has
  # since persisted 60 into /etc/asusd/asusd.ron of its own accord (seen
  # 2026-09-13), so the two agree; the oneshot stays because it is the
  # declaration and asusd's file is only a cache of it.
  # Its upstream unit sandboxes onto /etc/asusd and nothing creates that dir,
  # so without the tmpfiles line it dies status=226/NAMESPACE before exec and
  # burns its five restarts in a second (omarchy-fleet R37).
  services.asusd.enable = true;
  systemd.tmpfiles.rules = [ "d /etc/asusd 0755 root root -" ];

  # Quiet, on AC and on battery (Tom, 2026-10-11: "it really should not be in
  # performance mode", then, after the measurement below, "sure re Quiet let's
  # do that and i ll let you know if it's too slow or something, we'll move
  # back to the other mode"; the other mode is Balanced). Same 1080p VP9
  # playback: Balanced kept the fan at about 2250 rpm (62 C), Quiet at 0 rpm
  # (54 C) with the video still on the video engine at about 11% of one core.
  # This is a thin client: web, YouTube and Meet are the heaviest it ever
  # runs. To go back, set both platform_profile lines to Balanced. Until now asusd's own
  # undeclared default (platform_profile_on_ac: Performance, EPP performance)
  # fired on boot and on every dock replug, so the box sat in Performance on
  # the dock 24/7 and the fan ran at about 4000 rpm with a video playing.
  # Declared here so a replug or a wiped /etc/asusd cannot bring it back.
  # NixOS copies this as a 0644 file (not a store symlink), so asusd can still
  # rewrite it at runtime; every activation puts this text back.
  # profile_quiet_epp stays Power (what Quiet measured with). profile_balanced_epp
  # is BalancePerformance, the EPP power-profiles-daemon
  # applied with Balanced during the measurement, not asusd's BalancePower.
  services.asusd.asusdConfig.text = ''
    (
        charge_control_end_threshold: 60,
        base_charge_control_end_threshold: 100,
        disable_nvidia_powerd_on_battery: true,
        ac_command: "",
        bat_command: "",
        platform_profile_linked_epp: true,
        platform_profile_on_battery: Quiet,
        change_platform_profile_on_battery: true,
        platform_profile_on_ac: Quiet,
        change_platform_profile_on_ac: true,
        profile_quiet_epp: Power,
        profile_balanced_epp: BalancePerformance,
        profile_custom_epp: Performance,
        profile_performance_epp: Performance,
        ac_profile_tunings: {
            Performance: (
                enabled: false,
                group: {},
            ),
            Quiet: (
                enabled: false,
                group: {},
            ),
        },
        dc_profile_tunings: {
            Quiet: (
                enabled: false,
                group: {},
            ),
        },
        armoury_settings: {},
    )
  '';
  # asusd reads that file only at start and the upstream unit has no trigger,
  # so a switch that changes it restarts asusd; otherwise the old in-memory
  # Performance rule would keep firing until the next boot.
  systemd.services.asusd.restartTriggers = [ config.environment.etc."asusd/asusd.ron".text ];
  # asusd is the one owner of the platform profile here, as on the strix
  # (hosts/strix/default.nix). The fleet-wide power-profiles-daemon
  # (modules/common.nix) wrote the same sysfs knob and restored its own saved
  # profile seven seconds after asusd set one at boot (2026-10-11 journal).
  # Nothing in home/ talks to it.
  services.power-profiles-daemon.enable = lib.mkForce false;
  # And no TLP. nixos-hardware's common-pc-laptop (imported above) sets
  # `services.tlp.enable = lib.mkDefault (!power-profiles-daemon.enable)`, so
  # turning ppd off started TLP on the 2026-10-11 switch. Its defaults carry
  # PLATFORM_PROFILE_ON_AC="performance" (the exact rule removed above) and
  # USB autosuspend, which it applied to the Bluetooth adapter and the
  # iContact camera. asusd stays the single owner.
  services.tlp.enable = false;
  # thermald is OFF on this box (2026-09-13), measured: the UX8406MA gives it
  # nothing to act on — every ACPI trip is at 103 °C or above, the EC owns the
  # fan and exposes no curve (asusctl's fan-curve verb aborts with a core dump
  # here), and the firmware's own RAPL limits (20 W / 25 W in `quiet`) and the
  # silicon's 100 °C throttle are what actually protect the chip. What it did
  # instead: 1 h 50 min of CPU in 46 h of uptime polling eight dead EC sensors
  # (thermal_zone2… read 0.05 °C) at ~8 ms of blocked EC bus per read, and
  # one log line ever, "Unable to find a zone for STG0". Pure heat.
  services.thermald.enable = false;

  # Always docked: cap charge at 60% (ASUS "Maximum Lifespan"). The box lives
  # on the Thunderbolt dock 24/7, so unplugged runtime is not a cost, and a
  # cell held at 60% fades far slower than one held at 100% (health was 85%
  # after 271 cycles when this was set, 2026-09-13). Ordered after asusd so
  # its stored limit (100, /etc/asusd/asusd.ron) cannot overwrite this on
  # boot; a udev rule would lose that race.
  systemd.services.battery-charge-limit = {
    description = "Cap BAT0 charge at 60%";
    wantedBy = [ "multi-user.target" ];
    after = [ "asusd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = "echo 60 > /sys/class/power_supply/BAT0/charge_control_end_threshold";
  };

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
