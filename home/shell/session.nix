{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
# home/shell/session.nix: idle, lock and capture plumbing for the physical
# Sway seat, in one Home Manager module.
#
# What it is. The session layer of the consolidated shell (docs/shell/SHELL.md,
# rows "idle and lock" and "capture"). It declares a long running swayidle
# bound to sway-physical-session.target, a lock program (swaylock), and the
# capture tool set. It is gated on osConfig.myDisplay.enable exactly like
# home/vicinae.nix, so strix and nas get nothing from it.
#
# What it replaced, 2026-10-22 (dry run branch dryrun/shell-consolidation-2026-10-22).
#   MEASURED by grep in inventory/04-idle-lock-session.md: before this file no
#   idle policy and no lock program existed anywhere in home/, modules/ or
#   hosts/. swayidle was on the profile only as the one shot wake helper of
#   home/dot_local/bin/monitors-off (home/home.nix line 448).
#   REPORTED: the capture packages grim, slurp, satty, wl-clipboard and
#   wf-recorder sit in the flat package list of home/home.nix lines 444 through
#   461. This file now owns them; the wiring lane should delete those rows from
#   home.nix so the shell has one owner per package. Until then the duplicate is
#   harmless (same store paths).
#
# What is deliberately absent.
#   * Portals. modules/sway.nix (NixOS level) already declares
#     xdg.portal.config.sway-physical with ScreenCast and Screenshot = wlr and
#     the slurp chooser. That is the capture base for the later recall layer
#     (ruling R4). Home Manager's xdg.portal is not set here, because two
#     portal owners would fight over the same portals.conf.
#   * PAM. NixOS programs.sway (wayland-session.nix in the pinned nixpkgs)
#     already declares security.pam.services.swaylock = { } (MEASURED by
#     reading the store source of the flake's nixpkgs input).
#   * Lid. hosts/client/lid.nix stays the logind half (Q-15, 2026-09-11):
#     the lid is inert, F10 is the explicit dark verb.
#   * Idle inhibit. The portal Inhibit backend is "none" (modules/sway.nix)
#     and sway/rules.conf has no inhibit_idle rule. A rule such as
#     for_window [app_id="^google-chrome$"] inhibit_idle fullscreen belongs in
#     rules.conf, which this lane does not own.
#     TODO(tom, 2026-10-22): rule on idle inhibit for fullscreen Chrome before
#     the dim and dark timeouts go live.
#   * A lock binding. shell-lock is on PATH; binding it is the keymap lane's job.
#
# Rulings cited. R4 (THESIS, 2026-10-22): swayidle plus swaylock declared beside
# sway-local.conf, Mako stays, capture stays wlr portal plus PipeWire. R5: the
# lock is a later GPUIX port (ext-session-lock-v1, the gpuix-shell lock seam);
# swaylock is the stand in until then (see docs/shell/DEFERRED.md).
#
# Every number below is INFERRED: proposed by the drafter, not ruled by Tom.
let
  enabled = osConfig.myDisplay.enable;
  cfg = config.myShell.session;

  # INFERRED values, Tom has not ruled. TODO(tom, 2026-10-22): rule on all four.
  dimAfter = 600; # seconds idle before the backlight dims
  lockAfter = 900; # seconds idle before the lock, only when lockOnIdle is true
  darkAfter = 1200; # seconds idle before every output powers off
  dimPercent = 10; # dim level, percent of max_brightness of intel_backlight

  swaymsg = "${osConfig.programs.sway.package}/bin/swaymsg";
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  coreutils = "${pkgs.coreutils}/bin";

  # Dim and restore with a private state file, never brightnessctl --save:
  # F10 (bin/brightness off and restore, hosts/client/lid.nix) already owns
  # that save slot, and a shared slot would let an idle restore undo F10.
  # A panel that is already dark (F10) or dimmer than the target is left
  # alone. The dock daemon mirrors intel_backlight to eDP-2 every 500 ms
  # (REPORTED hosts/client/lid.nix), so one device is enough. On a host
  # without intel_backlight every verb exits 0.
  idleDim = pkgs.writeShellScript "shell-idle-dim" ''
    set -u
    dev=intel_backlight
    state="''${XDG_RUNTIME_DIR:-/tmp}/shell-idle-dim.level"
    case "''${1:-}" in
      dim)
        cur=$(${brightnessctl} -d "$dev" get 2>/dev/null) || exit 0
        max=$(${brightnessctl} -d "$dev" max 2>/dev/null) || exit 0
        target=$(( max * ${toString dimPercent} / 100 ))
        [ "$target" -ge 1 ] || target=1
        [ "$cur" -gt "$target" ] || exit 0
        printf '%s\n' "$cur" > "$state"
        exec ${brightnessctl} -q -d "$dev" set "$target"
        ;;
      restore)
        [ -r "$state" ] || exit 0
        level=$(${coreutils}/cat "$state")
        ${coreutils}/rm -f "$state"
        exec ${brightnessctl} -q -d "$dev" set "$level"
        ;;
      *)
        echo "usage: shell-idle-dim dim|restore" >&2
        exit 64
        ;;
    esac
  '';

  # The lock program. swaylock has no include directive, so the theme joins
  # through -C: when the theme pointer renders ~/.config/theme/swaylock.conf
  # it wins, otherwise the Home Manager config below (black, Anthropic Sans)
  # applies. No theme renders swaylock.conf today (REPORTED home/themes/*.nix
  # list noir, claude-dark, claude-light with no swaylock fragment).
  # TODO(theme lane, 2026-10-22): add a swaylock fragment to home/themes.
  # -f daemonizes once the ext-session-lock is held, so swayidle -w waits for
  # the lock before letting the machine sleep.
  shellLock = pkgs.writeShellScriptBin "shell-lock" ''
    set -u
    theme="$HOME/.config/theme/swaylock.conf"
    if [ -r "$theme" ]; then
      exec ${lib.getExe config.programs.swaylock.package} -f -C "$theme" "$@"
    fi
    exec ${lib.getExe config.programs.swaylock.package} -f "$@"
  '';
  lockCmd = "${shellLock}/bin/shell-lock";
in
{
  options.myShell.session.lockOnIdle = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Arm the idle lock (timeout lockAfter), the before-sleep lock and the
      loginctl lock-session handler. Off by default because the account may
      have no password to unlock with: modules/common.nix calls tom a locked,
      key-only account, and modules/user-password.nix delivers a hash only on
      fresh flashes (mutableUsers = true). With no password a PAM backed
      swaylock cannot be unlocked, and killing it leaves the ext-session-lock
      session red. TODO(tom, 2026-10-22): confirm the client has a password,
      then set this true in hosts/client.
    '';
  };

  config = lib.mkIf enabled {
    programs.swaylock = {
      enable = true;
      # Family name only, never a file: font bytes stay on the NAS (fonts README).
      settings = {
        color = "000000"; # black, matches output * bg #000000 in sway/layout.conf
        font = "Anthropic Sans";
        font-size = 24; # INFERRED
        indicator-caps-lock = true;
        show-failed-attempts = true;
        ignore-empty-password = true;
      };
    };

    services.swayidle = {
      enable = true;
      # Match Mako and Vicinae: the unit is PartOf, After and WantedBy the seat
      # target that modules/sway.nix starts from /etc/sway/physical-session.conf.
      systemdTargets = [ "sway-physical-session.target" ];
      timeouts = [
        {
          timeout = dimAfter;
          command = "${idleDim} dim";
          resumeCommand = "${idleDim} restore";
        }
      ]
      ++ lib.optionals cfg.lockOnIdle [
        {
          timeout = lockAfter;
          command = lockCmd;
        }
      ]
      ++ [
        {
          timeout = darkAfter;
          command = "${swaymsg} 'output * power off'";
          resumeCommand = "${swaymsg} 'output * power on'";
        }
      ];
      events = lib.mkIf cfg.lockOnIdle {
        before-sleep = lockCmd;
        lock = lockCmd;
      };
    };

    # Capture plumbing (screenshot, OCR, recording; bin/screenshot,
    # bin/screen-ocr-area). swayidle and swaylock arrive through their modules
    # above. All names MEASURED to exist in the flake's nixpkgs input:
    # grim 1.5.0, slurp 1.5.0, satty 0.21.1, wl-clipboard 2.3.0,
    # wf-recorder 0.6.0, brightnessctl 0.5.1, swayidle 1.9.0, swaylock 1.8.6.
    home.packages = [
      shellLock
      pkgs.grim
      pkgs.slurp
      pkgs.satty
      pkgs.wl-clipboard
      pkgs.wf-recorder
      pkgs.brightnessctl
    ];
  };
}
# Not verified
# * No unit was started; the swayidle chain has never run on the client.
# * Whether the client account has a password (gates lockOnIdle) is unknown.
# * The dim script was not executed; brightnessctl get and max output format
#   is assumed to be a bare integer.
# * No second reader (Tom's light verification rule, 2026-10-20).
