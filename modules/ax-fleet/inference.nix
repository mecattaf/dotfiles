{
  config,
  lib,
  ...
}:
# The inference node: the worker. "Halogen inference mainly on worker" (Tom,
# 2026-09-23). Halogen stays the worker's host service; sandboxes reach it at
# halogenEndpoint through Substrate's egress gateway on the NAS (SNAT to the
# NAS's LAN address). Nothing from this PR runs here at runtime and the worker
# is not switched in this motion: this file is one evaluation assertion, that
# Halogen's port stays open on the LAN leg.
let
  cfg = config.myAxFleet;
  on = cfg.enable && cfg.role == "inference";
  port = lib.toInt (lib.last (lib.splitString ":" cfg.halogenEndpoint));
  lanPorts = config.networking.firewall.interfaces.${cfg.lan.interface}.allowedTCPPorts or [ ];
in
{
  config = lib.mkIf on {
    assertions = [
      {
        assertion = builtins.elem port lanPorts;
        message = "modules/ax-fleet/inference.nix: Halogen's port ${toString port} must stay open on ${cfg.lan.interface}; ax sandboxes reach ${cfg.halogenEndpoint} through the egress gateway on the NAS.";
      }
      {
        assertion = !config.services.k3s.enable;
        message = "modules/ax-fleet/inference.nix: the worker is not a k3s node in this motion.";
      }
    ];
  };
}
