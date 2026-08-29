{
  inputs,
  pkgs,
  ...
}:
# The NAS base system rides nixpkgs-stable (#135), but a few packages are
# version-coupled to data or to a server this box already runs and must come
# from the main unstable input instead — currently the Immich module/package
# (hosts/nas/media.nix) and attic-server (hosts/nas/attic.nix: its SQLite
# migrations were written by the coordinator's unstable attic; stable's
# older attic refuses the "future" database).
#
# Instantiating unstable is not free, so it happens exactly once here and is
# handed to the rest of the host as the `unstablePkgs` module argument. Doing
# it per-file would evaluate a second full nixpkgs for every consumer.
#
# freshPkgs (2026-08-29): same once-only rule for the nixpkgs-fresh input.
# Sole NAS consumer today is ./kernel.nix — the main `nixpkgs` pin predates
# linux 7.2 (it even sits BELOW stable's 7.1.5 at the time of writing), so
# the kernel has to come from the rolling resolver. Anything else on this
# box that ever needs fresh must take this argument, not re-import.
{
  _module.args.unstablePkgs = import inputs.nixpkgs {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
  _module.args.freshPkgs = import inputs.nixpkgs-fresh {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
}
