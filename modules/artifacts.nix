{ lib, ... }:
# Fleet-wide artifact options (defaults from artifacts-defaults.nix — edit
# THERE, not here). The serving plane
# (Caddy + reaper) is coordinator-only and lives in caddy-artifacts.nix.
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
      description = "Caddy drop-dir: TTL-stamped site blocks + snapshot dirs.";
    };
    defaultTtlDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = defaults.defaultTtlDays;
      description = "Default artifact TTL in days; 'indefinite' is not a value.";
    };
  };
}
