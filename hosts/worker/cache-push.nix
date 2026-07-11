{ pkgs, ... }:
# worker → fleet cache AUTO-PUSH (refs #42). The worker is the designated
# builder; wire nix-daemon's post-build-hook so every closure it builds lands on
# the coordinator's atticd (http://coordinator:8080/fleet) the instant it is
# built. Cold hosts then substitute the prebuilt paths instead of the ~8h
# from-source rebuild of the llm-agents catalog. Counterpart to the SERVER half
# in hosts/coordinator/attic.nix and the substituter/trusted-key wiring in
# modules/common.nix.
#
# The hook runs as the nix-daemon (root), so ROOT must be `attic login`'d to the
# `fleet` cache with a push token (RUNTIME BOOTSTRAP — mint a worker-push token
# per hosts/coordinator/attic.nix, then `attic login fleet http://coordinator:8080
# <token>` as both tom and root). HOME is pinned so attic finds root's config.
#
# Best-effort by design: any failure (cache down, not logged in yet, offline) is
# logged to the daemon journal and swallowed (exit 0), and a wall-clock timeout
# caps the push so a slow/unreachable cache can never stall or fail a build.
let
  pushHook = pkgs.writeShellScript "attic-push-fleet" ''
    set -u
    # post-build-hook contract: $OUT_PATHS is the space-separated list of store
    # paths just built ($DRV_PATH is also set). Nothing to push if empty.
    [ -n "''${OUT_PATHS:-}" ] || exit 0
    # nix-daemon runs with a sparse env; point attic at root's logged-in config.
    export HOME=/root
    export XDG_CONFIG_HOME=/root/.config
    if ${pkgs.coreutils}/bin/timeout 60 \
         ${pkgs.attic-client}/bin/attic push fleet $OUT_PATHS >&2; then
      echo "attic-push-fleet: pushed to fleet: $OUT_PATHS" >&2
    else
      echo "attic-push-fleet: push failed (non-fatal), fleet cache unreachable or not logged in: $OUT_PATHS" >&2
    fi
    # Never propagate a non-zero status back to the build.
    exit 0
  '';
in
{
  nix.settings.post-build-hook = "${pushHook}";
}
