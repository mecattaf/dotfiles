{ lib, ... }:
# Retained artifact identity options for public publication and compatibility.
# Private Caddy hosting and its reaper were retired on 2026-11-08; declaring
# these metadata options does not install a serving plane.
let
  defaults = import ./artifacts-defaults.nix;
in
{
  options.myArtifacts = {
    zone = lib.mkOption {
      type = lib.types.str;
      default = defaults.zone;
      description = "Cloudflare zone hosting the artifact namespace.";
    };
    namespace = lib.mkOption {
      type = lib.types.str;
      default = defaults.namespace;
      description = "Domain under which every artifact slug is published.";
    };
    stateDir = lib.mkOption {
      type = lib.types.path;
      default = defaults.stateDir;
      description = "Legacy artifact state location; private serving is retired.";
    };
    defaultTtlDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = defaults.defaultTtlDays;
      description = "Default artifact TTL in days; 'indefinite' is not a value.";
    };
  };
}
