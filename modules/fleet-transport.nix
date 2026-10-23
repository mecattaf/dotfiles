{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myFleetTransport;
  host = config.networking.hostName;
  hosts = [
    "client"
    "nas"
    "strix-coordinator"
    "strix-worker"
  ];
  router = host == "nas";
  preferences = [
    "--hostname=${host}"
    "--accept-dns=false"
    "--ssh=false"
  ]
  ++ (
    if router then
      [
        "--advertise-routes=10.42.0.0/24"
        "--advertise-exit-node"
        "--accept-routes=false"
      ]
    else
      [
        "--accept-routes=true"
        "--exit-node=nas"
        "--exit-node-allow-lan-access=true"
      ]
  );
  policy = pkgs.writeText "fleet-transport.json" (
    builtins.toJSON {
      inherit hosts;
      tailnetSuffix = "tail8dd1.ts.net";
      subnet = "10.42.0.0/24";
      exitNode = "nas";
    }
  );
in
{
  options.myFleetTransport.enable = lib.mkOption {
    type = lib.types.bool;
    default = builtins.elem host hosts;
    description = "Official Tailscale fleet membership; NAS exit and LAN routing. Enrollment and key expiry are managed in the admin console.";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.elem host hosts && config.services.tailscale.enable;
        message = "Fleet transport requires an enabled Tailscale daemon on one of the four named fleet hosts; remove the former worker disable in #608.";
      }
      {
        assertion = config.services.tailscale.authKeyFile == null;
        message = "Fleet transport uses interactive enrollment and admin-console key expiry, without a delivered auth key.";
      }
      {
        assertion = !router || (config.myFleet.has "router" && config.myFleet.has "brain");
        message = "The NAS transport must retain both router and brain roles.";
      }
    ];
    services.tailscale = {
      enable = lib.mkDefault true;
      openFirewall = true;
      disableTaildrop = true;
      useRoutingFeatures = if router then "server" else "client";
      # Replace the previous fallback/client lists, including their stale flags.
      # No login-server means the official tailscale.com control plane.
      extraUpFlags = lib.mkForce preferences;
      extraSetFlags = lib.mkForce preferences;
    };
    environment.etc."fleet/transport.json".source = policy;
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "fleet-transport-check";
        runtimeInputs = [
          pkgs.python3
          pkgs.tailscale
        ];
        text = ''
          exec python3 ${../pkgs/fleet-transport/check.py} --policy ${policy} --host ${lib.escapeShellArg host} "$@"
        '';
      })
    ];
  };
}
