{
  inputs,
  pkgs,
  ...
}:
# The NAS base system rides nixpkgs-stable (#135), but a few packages are
# version-coupled to data or to a server this box already runs and must come
# from the main unstable input instead — currently the Immich module/package
# (hosts/nas/media.nix). attic-server was the other consumer until Attic was
# retired on 2026-11-25.
#
# Instantiating unstable is not free, so it happens exactly once here and is
# handed to the rest of the host as the `unstablePkgs` module argument. Doing
# it per-file would evaluate a second full nixpkgs for every consumer.
#
# freshPkgs (2026-08-29): same once-only rule for the nixpkgs-fresh input.
# Sole NAS consumer today is ./kernel.nix: the NAS follows the same current
# kernel series as the other hosts, independently of its stable userspace.
# Anything else on this box that needs fresh must take this argument,
# not re-import.
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
