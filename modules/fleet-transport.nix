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
  tailnetSuffix = "tail8dd1.ts.net";
  exitNode = "nas";
  # Only the strix pair routes its internet through the NAS. The Zenbook
  # (client) uses no exit node on any network (D-55 "no-exit-client"): with an
  # exit node a dead NAS cut its internet even on the Freebox fallback, which
  # defeats the T-58 Wi-Fi ladder. It still accepts the NAS subnet route, so
  # the house LAN stays reachable through the tailnet when roaming.
  exitNodeClients = [
    "strix-coordinator"
    "strix-worker"
  ];
  router = host == exitNode;
  exitClient = builtins.elem host exitNodeClients;
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
    else if exitClient then
      [
        "--accept-routes=true"
        "--exit-node=${exitNode}"
        "--exit-node-allow-lan-access=true"
      ]
    else
      [
        "--accept-routes=true"
        # An empty value clears any exit node a previous generation or a hand
        # `tailscale set` left in the persisted prefs.
        "--exit-node="
      ]
  );
  policy = pkgs.writeText "fleet-transport.json" (
    builtins.toJSON {
      inherit
        hosts
        tailnetSuffix
        exitNode
        exitNodeClients
        ;
      subnet = "10.42.0.0/24";
    }
  );
  # `tailscale set --exit-node=nas` resolves "nas" against the netmap. Right
  # after tailscaled starts (boot, or a switch that restarts it) the netmap is
  # not there yet, so the set failed with 'invalid value "nas" for
  # --exit-node' and failed the switch (Zenbook rollback 2026-10-25 05:12; the
  # strix pair at every boot). Wait, bounded, for BackendState Running with the
  # NAS node in the map (advertising the exit node where this host selects
  # it), then let the stock unit run `tailscale set`. A timeout or a node that
  # needs a login only ends the wait: the set then runs and reports its own
  # error, so nothing is hidden.
  netmapWaitSeconds = 120;
  netmapReady = pkgs.writeText "tailscaled-set-netmap-ready.jq" ''
    .BackendState == "Running"
    and ([.Self] + ((.Peer // {}) | [.[]])
         | map(select(. != null and .DNSName == $want
                      and (($needExit | not) or .ExitNodeOption == true)))
         | length > 0)
  '';
  waitForNetmap = pkgs.writeShellApplication {
    name = "tailscaled-set-wait-netmap";
    runtimeInputs = [
      config.services.tailscale.package
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      want=${lib.escapeShellArg "${exitNode}.${tailnetSuffix}."}
      need_exit=${if exitClient then "true" else "false"}
      deadline=$((SECONDS + ${toString netmapWaitSeconds}))
      parked=0
      state=unknown
      while :; do
        status=$(timeout 10 tailscale status --json 2>/dev/null || true)
        state=$(jq -r '.BackendState // "unknown"' <<<"$status" 2>/dev/null || echo unknown)
        [ -n "$state" ] || state=unknown
        if jq -e --arg want "$want" --argjson needExit "$need_exit" -f ${netmapReady} <<<"$status" >/dev/null 2>&1; then
          echo "tailscaled-set: netmap ready (BackendState Running, $want visible) after $SECONDS s"
          exit 0
        fi
        case "$state" in
          NeedsLogin | NeedsMachineAuth | Stopped) parked=$((parked + 1)) ;;
          *) parked=0 ;;
        esac
        if [ "$parked" -ge 5 ]; then
          echo "tailscaled-set: BackendState $state (needs an operator); applying the preferences without a netmap" >&2
          exit 0
        fi
        if [ "$SECONDS" -ge "$deadline" ]; then
          echo "tailscaled-set: no usable netmap after ${toString netmapWaitSeconds} s (BackendState $state, $want not visible); applying the preferences anyway" >&2
          exit 0
        fi
        sleep 2
      done
    '';
  };
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
      {
        assertion = host != "client" || !exitClient;
        message = "The Zenbook selects no exit node (D-55 no-exit-client): a NAS outage must not take its internet on the Freebox.";
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
    systemd.services.tailscaled-set = {
      serviceConfig = {
        ExecStartPre = [ (lib.getExe waitForNetmap) ];
        # The wait is bounded by itself; this only caps a hung `tailscale set`.
        TimeoutStartSec = "${toString (netmapWaitSeconds + 60)}s";
      };
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
