{ config, lib, ... }:
{
  options.myFleet = {
    roles = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "brain"
          "compute"
          "seat"
          "router"
        ]
      );
      default = [ ];
      description = "Responsibilities assigned to this fleet host.";
    };

    has = lib.mkOption {
      type = lib.types.functionTo lib.types.bool;
      readOnly = true;
      internal = true;
      default = role: builtins.elem role config.myFleet.roles;
      description = "Whether this host has the requested fleet role.";
    };

    active = lib.mkOption {
      type = lib.types.functionTo lib.types.bool;
      readOnly = true;
      internal = true;
      default = name: !((import ./mesh-registry.nix).${name}.dormant or false);
      description = "Whether the named fleet host is in service; a dormant row in modules/mesh-registry.nix is not.";
    };
  };
}
