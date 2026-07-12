{ config, lib, ... }:
# Fleet-wide artifact options (defaults from artifacts-defaults.nix — edit
# THERE, not here) + the worker's live-artifact port range. The serving plane
# (Caddy + reaper) is coordinator-only and lives in caddy-artifacts.nix.
let
  defaults = import ./artifacts-defaults.nix;
  cfg = config.myArtifacts;
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
    livePortRange = lib.mkOption {
      type = lib.types.attrsOf lib.types.port;
      default = defaults.livePortRange;
      description = "Worker port window for exposing microVM guest ports.";
    };
  };

  # Worker only: let the coordinator's Caddy reach forwarded guest ports over
  # the tailnet. The range is deliberately small — one publishable port per
  # concurrently-exposed VM, not a general hole.
  # `or null`: myCluster is defined only on the Strix pair (modules/strix.nix);
  # this module is fleet-wide (via common.nix), so guard the reference or the
  # zenbook (no myCluster option) fails to evaluate at all.
  config = lib.mkIf ((config.myCluster.role or null) == "worker") {
    networking.firewall.interfaces.tailscale0.allowedTCPPorts =
      lib.range cfg.livePortRange.from cfg.livePortRange.to;
  };
}
