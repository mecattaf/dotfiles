{ config, pkgs, ... }:
# Cache warmer — the "build ONCE" half of fleet auto-update (modules/auto-update.nix).
# Nightly at 02:00, BEFORE any host's nixos-upgrade timer, build every host's toplevel
# from main and push the full closures to the fleet cache. The post-build-hook
# (cache-push.nix) already pushes what gets COMPILED here; this explicit push also
# covers substituted deps, so the 04:30 coordinator and 06:00 zenbook runs are pure
# eval + substitution. Best-effort per host: one broken host config must not starve
# the others' cache, and the whole unit is non-fatal (a failure just means the later
# runs compile/offload as usual). refs #42.
#
# Reuses root's `attic login fleet` from the cache-push.nix RUNTIME BOOTSTRAP; if that
# login was never done, this fails visibly at 02:00 (the earliest warning you get).
let
  flakeRef = "github:mecattaf/dotfiles/main";
  prebuild = pkgs.writeShellScript "fleet-prebuild" ''
    set -u
    # attic login state lives in root's config; nix-daemon gives a sparse env.
    export HOME=/root XDG_CONFIG_HOME=/root/.config
    status=0
    for h in coordinator worker zenbook-duo; do
      echo "fleet-prebuild: building $h" >&2
      if out="$(${config.nix.package}/bin/nix build --refresh --no-link --print-out-paths \
            "${flakeRef}#nixosConfigurations.$h.config.system.build.toplevel")"; then
        ${pkgs.attic-client}/bin/attic push fleet $out >&2 || status=1
      else
        echo "fleet-prebuild: build of $h FAILED" >&2
        status=1
      fi
    done
    exit $status
  '';
in
{
  systemd.services.fleet-prebuild = {
    description = "Build all fleet hosts' toplevels from main and push to the fleet cache";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    startAt = "02:00";
    # Same failure banner as nixos-upgrade (modules/fleet-notify.nix): a cold cache
    # (unwarmed builds) is worth surfacing, and this box is headless.
    unitConfig = {
      OnFailure = "fleet-update-alert@%n.service";
      OnSuccess = "fleet-update-clear@%n.service";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = prebuild;
      TimeoutStartSec = "infinity"; # worst case is an hours-long cold build
      Nice = 10; # yield to interactive offloaded builds
    };
  };
  # Fire on next boot if the box was down at 02:00.
  systemd.timers.fleet-prebuild.timerConfig.Persistent = true;
}
