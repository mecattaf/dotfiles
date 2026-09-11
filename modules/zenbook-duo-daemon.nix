{
  config,
  lib,
  pkgs,
  ...
}:
# zenbook-duo-daemon — the ASUS Zenbook Duo UX8406MA dock contract, as a root
# system service. Imported by hosts/client/default.nix only.
#
# What it does (PegasisForever/zenbook-duo-daemon 1.2.0, pkgs/zenbook-duo-daemon.nix):
#   * keyboard (USB 0b05:1b2c) snapped onto the bottom panel → writes `off` to
#     the eDP-2 connector's force-status file; detached → `on`. The kernel
#     raises a real hotplug uevent either way, so this is compositor-agnostic —
#     niri drops or adds the output and kanshi re-applies a profile.
#   * copies intel_backlight (eDP-1) → card1-eDP-2-backlight every 500 ms, so
#     F1/F2 on eDP-1 carry to eDP-2 and a brightness of 0 darkens both panels
#     (that is what the F10 backlight toggle in home/home.nix's niri-local.kdl
#     branch relies on). It copies without comparing: per-panel adjustment of
#     eDP-2 alone is therefore ineffective while this runs — accepted.
#   * re-emits the keyboard's vendor Fn keys through uinput (brightness,
#     mic-mute, Ctrl+. for emoji) under fn_lock.
#   * a suspend/resume pipe, driven by the two sleep hooks below.
#
# Root, because raw USB control transfers and DRM sysfs writes need it — same
# posture as asusd and thermald. IDs are options, not literals, because the
# DRM card index is enumeration order: the values below were re-read from the
# metal on 2026-09-11 (lsusb 0b05:1b2c, /sys/class/drm/card1-eDP-2/status,
# /sys/class/backlight/card1-eDP-2-backlight).
#
# History: dotfiles never had this while the laptop was `zenbook-duo`
# (2026-06 → 2026-08-30); the slot was filled by ntm, which never auto-started.
# omarchy-fleet wrote this module on 2026-09-08 and ran it on this exact
# machine; it came back with the laptop on 2026-09-11 (host `client`).
let
  cfg = config.services.zenbook-duo-daemon;
  pipe = "/run/zenbook-duo-daemon.pipe";
  configToml = pkgs.writeText "zenbook-duo-daemon-config.toml" ''
    usb_vendor_id = "${cfg.usbVendorId}"
    usb_product_id = "${cfg.usbProductId}"
    fn_lock = true
    secondary_display_status_path = "${cfg.drmStatusPath}"
    primary_backlight_path = "/sys/class/backlight/intel_backlight/brightness"
    secondary_backlight_path = "${cfg.secondaryBacklightPath}"
    pipe_path = "${pipe}"
    idle_timeout_seconds = 300

    [keyboard_backlight_key]
    KeyboardBacklight = true
    [brightness_down_key]
    KeyBind = ["KEY_BRIGHTNESSDOWN"]
    [brightness_up_key]
    KeyBind = ["KEY_BRIGHTNESSUP"]
    [swap_up_down_display_key]
    NoOp = true
    [microphone_mute_key]
    KeyBind = ["KEY_MICMUTE"]
    [emoji_picker_key]
    KeyBind = ["KEY_LEFTCTRL", "KEY_DOT"]
    [myasus_key]
    NoOp = true
    [toggle_secondary_display_key]
    ToggleSecondaryDisplay = true
  '';
  pipeSay = msg: "${pkgs.coreutils}/bin/timeout 1 ${pkgs.bash}/bin/bash -c 'echo ${msg} > ${pipe} || true'";
  sleepTargets = [
    "suspend.target"
    "hibernate.target"
    "hybrid-sleep.target"
    "suspend-then-hibernate.target"
  ];
in
{
  options.services.zenbook-duo-daemon = {
    enable = lib.mkEnableOption "the Zenbook Duo dock/keyboard/display daemon";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../pkgs/zenbook-duo-daemon.nix { };
    };
    usbVendorId = lib.mkOption {
      type = lib.types.str;
      default = "0b05";
    };
    usbProductId = lib.mkOption {
      type = lib.types.str;
      # UX8406MA detachable keyboard; `lsusb -d 0b05:1b2c` while docked.
      default = "1b2c";
    };
    drmStatusPath = lib.mkOption {
      type = lib.types.str;
      # `ls /sys/class/drm | grep eDP` — the card index is enumeration order.
      default = "/sys/class/drm/card1-eDP-2/status";
    };
    secondaryBacklightPath = lib.mkOption {
      type = lib.types.str;
      default = "/sys/class/backlight/card1-eDP-2-backlight/brightness";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    environment.etc."zenbook-duo-daemon/config.toml".source = configToml;

    systemd.services.zenbook-duo-daemon = {
      description = "Zenbook Duo dock/keyboard/display daemon";
      after = [ "sysinit.target" ];
      wantedBy = [ "multi-user.target" ];
      restartIfChanged = true;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/zenbook-duo-daemon run --config-path /etc/zenbook-duo-daemon/config.toml";
        Restart = "on-failure";
        RestartSec = 1;
      };
    };

    # Suspend/resume hooks: the daemon's own units, ported. If the 500 ms
    # reconciliation loop proves too slow after resume, the post-sleep hook is
    # where an explicit display re-assert would go — verify on hardware first.
    systemd.services.zenbook-duo-daemon-pre-sleep = {
      before = [ "sleep.target" ];
      wantedBy = [ "sleep.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pipeSay "suspend_start";
      };
    };
    systemd.services.zenbook-duo-daemon-post-sleep = {
      after = sleepTargets;
      wantedBy = sleepTargets;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pipeSay "suspend_end";
      };
    };
  };
}
