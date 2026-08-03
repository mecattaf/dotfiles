{
  config,
  lib,
  pkgs,
  ...
}:
# `rollback-offline` — a rollback that cannot fail for network reasons. Refs #106.
#
# `nixos-rebuild --rollback` is unusable on this fleet, and always has been: it
# re-execs itself through `nix-build '<nixpkgs/nixos>'`, which is a *channel*
# lookup. This flake registers no channel, has no
# /nix/var/nix/profiles/per-user/root/channels and no /etc/nixos/configuration.nix,
# so `<nixpkgs/nixos>` cannot resolve and the command aborts — with or without an
# uplink. That was discovered the hard way on 2026-07-25, when the coordinator
# lost its wifi after activating a bad generation and the only way back was a
# physical reboot into the boot menu.
#
# This command does the one thing that involves zero evaluation and zero
# network: flip the system profile symlink to an already-built generation and
# run that generation's own switch-to-configuration. Everything it touches is
# on local disk.
#
#   rollback-offline           roll back one generation (current → previous)
#   rollback-offline 118       switch to a specific generation number
#   rollback-offline --list    show available generations (no root needed)
let
  rollback-offline = pkgs.writeShellScriptBin "rollback-offline" ''
    set -eu
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}:$PATH

    profile=/nix/var/nix/profiles/system
    nixenv=${config.nix.package.out}/bin/nix-env

    case "''${1-}" in
      -h|--help)
        cat <<'EOF'
    rollback-offline — activate a previous NixOS generation with no network and no eval.

      rollback-offline            roll back one generation      (root)
      rollback-offline <N>        switch to generation <N>      (root)
      rollback-offline --list     list generations              (any user)

    Unlike `nixos-rebuild --rollback` this never evaluates the flake, never
    resolves <nixpkgs/nixos>, and never contacts a substituter or registry.
    EOF
        exit 0
        ;;
      -l|--list)
        # Deliberately NOT `nix-env --list-generations`: that takes a write lock
        # on the profile and so needs root. Reading the generation symlinks
        # directly works as any user, which matters when you are triaging from a
        # console before deciding to sudo. `stat` sees the LINK's mtime (GNU
        # stat lstats unless -L), i.e. when the generation was created.
        current=$(basename "$(readlink "$profile" 2>/dev/null || echo none)")
        booted=$(readlink -f /run/booted-system 2>/dev/null || echo none)
        for link in "$profile"-*-link; do
          if [ ! -L "$link" ]; then continue; fi
          gen=''${link##*/system-}
          gen=''${gen%-link}
          mark=""
          if [ "$(basename "$link")" = "$current" ]; then mark="$mark (current)"; fi
          if [ "$(readlink -f "$link")" = "$booted" ]; then mark="$mark (booted)"; fi
          printf '%6s  %s%s\n' "$gen" "$(stat -c %y "$link" | cut -d. -f1)" "$mark"
        done | sort -n
        exit 0
        ;;
    esac

    if [ "$(id -u)" -ne 0 ]; then
      echo "rollback-offline: must run as root (try: sudo rollback-offline)" >&2
      exit 1
    fi

    if [ "$#" -eq 0 ]; then
      "$nixenv" --profile "$profile" --rollback
    else
      "$nixenv" --profile "$profile" --switch-generation "$1"
    fi

    target=$(readlink -f "$profile")
    echo "rollback-offline: activating $target"
    # Run the TARGET generation's own switch-to-configuration (the profile
    # symlink now points at it), so the activation logic matches the config
    # being activated. This also reinstalls the bootloader entry, making the
    # rollback survive a reboot.
    exec "$profile/bin/switch-to-configuration" switch
  '';
in
{
  environment.systemPackages = [ rollback-offline ];
}
