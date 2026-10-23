{ lib, ... }:
let
  registry = import ../modules/mesh-registry.nix;
  targets = {
    strix-coordinator = "strix-coordinator";
    strix-worker = "strix-worker";
    strix = "strix-coordinator"; # temporary compatibility alias
    nas = "nas";
    client = "client";
  };
in
assert builtins.all (name: builtins.hasAttr name registry) (builtins.attrValues targets);
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = lib.mapAttrs (_: target: {
      HostName = target;
      User = "tom";
      IdentityFile = "~/.ssh/id_ed25519";
      IdentitiesOnly = true;
      StrictHostKeyChecking = "yes";
    }) targets;
  };
}
