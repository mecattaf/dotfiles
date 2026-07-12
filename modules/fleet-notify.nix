{
  config,
  lib,
  pkgs,
  ...
}:
# Fleet auto-update failure NOTIFIER (modules/auto-update.nix companion). A nightly
# nixos-upgrade / fleet-prebuild that fails must not fail silently — especially on the
# headless worker, the box whose builds everything else depends on.
#
# Channel choice: this fleet has no notification daemon (niri ships none) and the fish
# config is an out-of-store symlink that dotfiles-bootstrap only clones-if-absent, so
# neither notify-send nor an out-of-store fish file reaches the worker reliably. Instead:
#   • OnFailure writes a world-readable marker to /var/lib/fleet-update/ and MIRRORS it
#     over the mesh to the always-on coordinator (root SSH, best-effort) — so the
#     headless worker's failures surface where tom actually looks.
#   • OnSuccess clears that source's marker (self-healing: a blip that later succeeds
#     stops nagging).
#   • A fish login banner (programs.fish.interactiveShellInit — IN-STORE, so it updates
#     atomically with the rebuild, unlike the out-of-store fish checkout) prints any
#     active markers on every new interactive shell / zmx pane.
#
# Wired onto nixos-upgrade here (fleet-wide); fleet-prebuild wires its own OnFailure in
# hosts/worker/fleet-prebuild.nix. refs #42.
let
  host = config.networking.hostName;
  markerDir = "/var/lib/fleet-update";

  # $1 = fail | clear ; $2 = source unit name (e.g. nixos-upgrade.service).
  # host is baked at eval time (deterministic; the module is evaluated per host).
  # Mirror target is the coordinator over root's outbound mesh key (secrets.nix);
  # a no-op on the coordinator itself and whenever the key/cache is unreachable.
  fleetNotify = pkgs.writeShellScript "fleet-notify" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.openssh
      ]
    }:$PATH"
    mode="$1"; unit="$2"
    host="${host}"
    dir="${markerDir}"
    key=/run/agenix/ssh-root-key
    marker="$dir/$host-$unit.fail"
    install -d -m 0755 "$dir"

    # Run a command on the coordinator to keep its mirror of the marker in sync.
    # Best-effort: never let a mirror failure fail this handler.
    mirror() {
      [ "$host" = coordinator ] && return 0
      [ -r "$key" ] || return 0
      ssh -i "$key" -o BatchMode=yes -o ConnectTimeout=5 \
          -o StrictHostKeyChecking=accept-new root@coordinator "$1" >/dev/null 2>&1 || true
    }

    case "$mode" in
      fail)
        line="$host/$unit failed $(date '+%Y-%m-%d %H:%M') — journalctl -u $unit -b"
        printf '%s\n' "$line" > "$marker"; chmod 0644 "$marker"
        mirror "install -d -m 0755 '$dir'; printf '%s\n' '$line' > '$marker'; chmod 0644 '$marker'"
        ;;
      clear)
        # Only touch the mirror if we actually cleared something locally — avoids a
        # nightly SSH to the coordinator on every ordinary success.
        if [ -e "$marker" ]; then
          rm -f "$marker"
          mirror "rm -f '$marker'"
        fi
        ;;
    esac
    exit 0
  '';
in
{
  # Ensure the marker dir exists before any fish shell reads it.
  systemd.tmpfiles.rules = [ "d ${markerDir} 0755 root root -" ];

  # OnFailure/OnSuccess targets. Templated on the source unit (%i) so nixos-upgrade
  # and fleet-prebuild share one pair of handlers. Run as root: needs the system
  # journal reference in the marker line and root's outbound mesh key for the mirror.
  systemd.services."fleet-update-alert@" = {
    description = "Fleet auto-update: record failure of %i";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${fleetNotify} fail %i";
    };
  };
  systemd.services."fleet-update-clear@" = {
    description = "Fleet auto-update: clear failure marker for %i";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${fleetNotify} clear %i";
    };
  };

  # Wire the native nixos-upgrade unit (autoUpgrade, fleet-wide). %n expands to this
  # unit's own name, becoming the template instance.
  systemd.services.nixos-upgrade.unitConfig = {
    OnFailure = "fleet-update-alert@%n.service";
    OnSuccess = "fleet-update-clear@%n.service";
  };

  # Login banner: surface any active markers on every interactive fish shell. Cheap
  # (a glob + a test); silent when there are none. `set` on a non-matching glob yields
  # an empty list without erroring, so the guard is safe when the dir is empty.
  programs.fish.interactiveShellInit = lib.mkAfter ''
    if status is-interactive
        set -l __fu ${markerDir}/*.fail
        if set -q __fu[1]
            set_color -o red; echo "⚠  fleet auto-update FAILED:"; set_color normal
            for __f in $__fu
                echo "   • "(cat $__f)
            end
            echo "   clear with: sudo rm ${markerDir}/*.fail"
        end
    end
  '';
}
