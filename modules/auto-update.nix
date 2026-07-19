{
  config,
  lib,
  pkgs,
  ...
}:
# Fleet auto-update — PULL model. Every host re-fetches github:mecattaf/dotfiles/main
# on a daily timer and switches to it; the trigger is simply YOUR push to main. The
# committed flake.lock pins all inputs, so nothing here bumps nixpkgs/kernel/etc —
# lock bumps stay a deliberate manual act (that is the only door kernel churn enters
# through, so you always know a worker reboot is coming). Native `system.autoUpgrade`
# (a systemd timer + nixos-rebuild wrapper) rather than a bespoke script: it already
# handles flake --refresh, Persistent catch-up, and the kernel-diff reboot dance.
#
# STAGGER (Europe/Paris) so the heavy build happens ONCE and the rest substitute:
#   02:00  worker      fleet-prebuild  — builds all 3 hosts' toplevels, pushes to attic
#                                        (hosts/worker/fleet-prebuild.nix)
#   03:30  worker      nixos-upgrade   — toplevel already in store → near-instant switch;
#                                        reboots ONLY on a kernel change, window 03:00–05:00
#   04:30  coordinator nixos-upgrade   — substitutes from the fleet cache; never reboots
#   06:00  zenbook     nixos-upgrade   — substitutes; battery-gated; never reboots
# Any straggler compile still offloads to the worker via modules/build-offload.nix.
#
# Not gated on mySecrets: needs only the PUBLIC repo and the PUBLIC-pull fleet cache.
# Degrades safely everywhere — a failed fetch/eval/build/switch leaves the running
# generation untouched and the next day's timer retries. See common.nix
# nix.settings.{connect-timeout,fallback} for the dead-substituter degradation.
let
  host = config.networking.hostName;

  # Per-host policy. Only the headless worker may auto-reboot (and only for a kernel
  # change): the coordinator's persistent zmx/tally sessions must survive, and a
  # laptop reboots naturally often enough.
  policy =
    {
      worker = {
        dates = "03:30";
        allowReboot = true;
      };
      coordinator = {
        dates = "04:30";
        allowReboot = false;
      };
      zenbook-duo = {
        dates = "06:00";
        allowReboot = false;
      };
    }
    .${host};

  # zenbook power gate: proceed on AC, OR on battery ≥ 50%. ExecCondition contract:
  # exit 0 → run the unit; non-zero → SKIP it cleanly (not a failure). Reads sysfs
  # directly (authoritative, no upower dependency).
  powerOk = pkgs.writeShellScript "nixos-upgrade-power-ok" ''
    for ps in /sys/class/power_supply/*; do
      [ -r "$ps/type" ] || continue
      case "$(cat "$ps/type")" in
        Mains)   [ "$(cat "$ps/online" 2>/dev/null)" = "1" ] && exit 0 ;;
        Battery) cap="$(cat "$ps/capacity" 2>/dev/null)" || continue
                 [ -n "$cap" ] && [ "$cap" -ge 50 ] && exit 0 ;;
      esac
    done
    echo "nixos-upgrade: skipping — on battery below 50%" >&2
    exit 1
  '';
in
{
  system.autoUpgrade = {
    enable = true;
    # Branch pinned explicitly (same rationale as dotfiles-bootstrap.nix). The module
    # appends `--refresh --flake <this>` itself, so each run re-resolves main's head.
    flake = "github:mecattaf/dotfiles/main";
    operation = "switch"; # live activation — no reboot except kernel/initrd changes.
    upgrade = false; # `--upgrade` is channel machinery; meaningless in flake mode.
    # Re-resolve nixpkgs-fresh to nixos-unstable HEAD on every run (flake.nix input
    # comment) — the "hot" overlay packages (google-chrome, uv) get whatever's newest
    # each night, without a flake.lock bump touching the deliberately-lagging main
    # nixpkgs pin.
    flags = [
      "--override-input"
      "nixpkgs-fresh"
      "github:NixOS/nixpkgs/nixos-unstable"
    ];
    dates = policy.dates;
    persistent = true; # laptop asleep/off at its time → fires on next wake/boot.
    randomizedDelaySec = "0"; # the stagger above is deliberate; jitter would defeat it.
    allowReboot = policy.allowReboot;
    # worker only: nixos-rebuild boot, then reboot IFF the booted kernel/initrd/modules
    # differ from the new generation, and only inside this window. The 03:30 run lands
    # inside it, so a kernel bump reboots the same night.
    rebootWindow = lib.mkIf policy.allowReboot {
      lower = "03:00";
      upper = "05:00";
    };
  };

  # Battery/power gate — zenbook only.
  systemd.services.nixos-upgrade.serviceConfig.ExecCondition =
    lib.mkIf (host == "zenbook-duo")
      "${powerOk}";

  # Daily generation churn needs a GC counterweight; keep 14 days of rollback depth.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
}
