{
  config,
  lib,
  pkgs,
  rollingInputOverrides,
  ...
}:
# Fleet update EXECUTION units. The coordinator's tally calendar producers own the
# schedule and admission; this module retains NixOS's proven `nixos-upgrade.service`
# implementation on each target but deliberately disables its native timer.
#
# Every invocation re-fetches github:mecattaf/dotfiles/main and switches to it. The
# committed flake.lock pins ordinary inputs, while the package-only inputs declared
# as rollingInputOverrides in flake.nix are deliberately re-resolved at build time.
# Lock bumps remain an operator decision and are the only door through which main
# nixpkgs/kernel/Mesa churn enters the fleet.
#
# TALLY CALENDAR (Europe/Paris), declared centrally in home/tally.nix:
#   02:00  worker prebuild       build
#   03:30  worker activation     build + worker-gpu (atomic)
#   04:30  coordinator activation build + coordinator-gpu (atomic)
#   06:00  zenbook activation    build; best-effort only when online
#
# Low priority makes an activation wait for existing work. hardPreempt=false on the
# pools means it cannot kill a running job, and the shared build gate preserves the
# old prebuild→activation ordering even when an earlier stage runs long. Unattended
# reboot is disabled: releasing a lease before a delayed reboot would admit a fresh
# task only to kill it a minute later. Kernel activation is a separate queued action.
#
# Not gated on mySecrets: needs only the PUBLIC repo and the PUBLIC-pull fleet cache.
# Degrades safely everywhere — a failed fetch/eval/build/switch leaves the running
# generation untouched and the next Tally calendar firing retries. See common.nix
# nix.settings.{connect-timeout,fallback} for the dead-substituter degradation.
let
  host = config.networking.hostName;
  rollingInputFlags = lib.concatMap (input: [
    "--override-input"
    input.name
    input.url
  ]) rollingInputOverrides;

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
    operation = "switch"; # live activation; a new kernel awaits a separately queued reboot.
    upgrade = false; # `--upgrade` is channel machinery; meaningless in flake mode.
    # Re-resolve the isolated rolling package inputs at HEAD on every run. This
    # keeps llm-agents and both accelerator catalogs fresh without using the same
    # door for the deliberately-reviewed main nixpkgs/kernel/Mesa pin.
    flags = rollingInputFlags;
    allowReboot = false;
  };

  # Keep the service generated above, but remove both paths by which the NixOS
  # module would make it autonomous. Tally is the sole fleet-update clock.
  systemd.services.nixos-upgrade.startAt = lib.mkForce [ ];
  systemd.timers.nixos-upgrade.enable = false;

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
