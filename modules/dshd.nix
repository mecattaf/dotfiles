{
  config,
  inputs,
  lib,
  ...
}:
let
  entrypoint = config.home-manager.users.tom.programs.dsh.package.override { permissive = true; };
in
{
  imports = [ inputs.dshd.nixosModules.default ];

  config = lib.mkIf (config.myFleet.has "brain") {
    services.dshd.enable = true;
    # Upstream reserves "default" for the automatic link to the only release.
    services.dshd.releases.nas = {
      dsh = entrypoint;
      unsetEnvironment = entrypoint.unsetEnvironment;
    };
  };
}
