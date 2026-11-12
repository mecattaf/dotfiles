# `nix build .#<name>` builds the derivation a host installs, not a lookalike.
# For every flake package that some host installs (environment.systemPackages,
# fonts.packages or a Home Manager user's home.packages), the export must be
# that host's own derivation. The NAS evaluates from nixpkgs-stable (mkHost
# hostNixpkgs) and the flake-level `pkgs` from nixpkgs, so the same name is two
# derivations there. Where installing hosts disagree, the export must be one
# of theirs, and the comment in flake.nix says whose. A package that only a
# unit's ExecStart names is not seen here.
{
  pkgs,
  lib,
  self,
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  exported = self.packages.${system};
  hosts = lib.mapAttrs (
    _: configuration:
    let
      inherit (configuration) config;
      installed =
        config.environment.systemPackages
        ++ config.fonts.packages
        ++ lib.concatMap (user: user.home.packages) (
          builtins.attrValues (config.home-manager.users or { })
        );
    in
    {
      inherit (configuration) pkgs;
      drvPaths = lib.catAttrs "drvPath" installed;
    }
  ) self.nixosConfigurations;
  # The host's own derivation for an exported name, or null. tryEval: the name
  # may also be a nixpkgs attribute that does not evaluate there (broken,
  # unsupported), and no host installs that one.
  hostDrvPath =
    host: name:
    let
      attempt = builtins.tryEval (host.pkgs.${name}.drvPath or null);
    in
    if attempt.success then attempt.value else null;
  installers =
    name:
    lib.filterAttrs (
      _: host:
      let
        drvPath = hostDrvPath host name;
      in
      drvPath != null && builtins.elem drvPath host.drvPaths
    ) hosts;
  mismatches = lib.concatMap (
    name:
    let
      owners = installers name;
      shipped = lib.mapAttrsToList (_: host: hostDrvPath host name) owners;
    in
    lib.optional (
      owners != { } && !(builtins.elem exported.${name}.drvPath shipped)
    ) "${name} (installed by ${lib.concatStringsSep ", " (builtins.attrNames owners)})"
  ) (builtins.attrNames exported);
in
assert lib.assertMsg (mismatches == [ ])
  "packages.${system} is not the derivation its host installs: ${lib.concatStringsSep "; " mismatches}";
pkgs.runCommand "packages-host-drv" { } ''
  touch $out
''
