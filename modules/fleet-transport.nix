{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myFleetTransport;
  host = config.networking.hostName;
  # Tailnet members (Tom, 2026-10-25: "default vanilla, make it work"). The
  # NAS is the only exit node and subnet router. The Zenbook (client) roams with
  # its own login. strix-coordinator keeps its own login as the independent
  # recovery box ("strix coordiantor having its own tailscale login allows us to
  # do the recovery process"). strix-worker is not on the tailnet at all
  # ("worker's tailnet login: fine, and i was thinking let's not"); it is
  # reached over the house LAN.
  hosts = [
    "client"
    "nas"
    "strix-coordinator"
  ];
  tailnetSuffix = "tail8dd1.ts.net";
  exitNode = "nas";
  # No host selects an exit node. The Zenbook's internet goes out through
  # whichever Wi-Fi it is on, so a dead NAS leaves the Freebox rung of the T-58
  # Wi-Fi ladder usable (D-55 "no-exit-client"); Tom can pick the NAS exit by
  # hand on the go. The coordinator reaches the internet directly through the
  # BE550, so it stays usable when the NAS is down.
  exitNodeClients = [ ];
  router = host == exitNode;
  # Only the roaming Zenbook needs the NAS subnet route (the house LAN through
  # the tailnet when it is away) and MagicDNS (nas.tail8dd1.ts.net, the Herdr
  # web UI's HTTPS name). Tailscale's defaults there; resolved keeps the Wi-Fi
  # DNS as the default route and sends only the tailnet domain to MagicDNS.
  # The coordinator is on the LAN and must not depend on the NAS route.
  roaming = host == "client";
  preferences = [
    "--hostname=${host}"
    "--accept-dns=${lib.boolToString roaming}"
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
        "--accept-routes=${lib.boolToString roaming}"
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
  # Right after tailscaled starts (boot, or a switch that restarts it) the
  # backend has no netmap yet. A `tailscale set` that names a peer then fails
  # ('invalid value "nas" for --exit-node' rolled back the 2026-10-25 Zenbook
  # deploy and failed every strix boot). No host names a peer now, but the set
  # still runs against a backend that is up: wait, bounded, for BackendState
  # Running with the NAS node in the map, then let the stock unit run
  # `tailscale set`. A timeout or a node that needs a login only ends the wait:
  # the set then runs and reports its own error, so nothing is hidden.
  netmapWaitSeconds = 120;
  netmapReady = pkgs.writeText "tailscaled-set-netmap-ready.jq" ''
    .BackendState == "Running"
    and ([.Self] + ((.Peer // {}) | [.[]])
         | map(select(. != null and .DNSName == $want))
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
      deadline=$((SECONDS + ${toString netmapWaitSeconds}))
      parked=0
      state=unknown
      while :; do
        status=$(timeout 10 tailscale status --json 2>/dev/null || true)
        state=$(jq -r '.BackendState // "unknown"' <<<"$status" 2>/dev/null || echo unknown)
        [ -n "$state" ] || state=unknown
        if jq -e --arg want "$want" -f ${netmapReady} <<<"$status" >/dev/null 2>&1; then
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
    description = "Official Tailscale fleet membership (client, nas, strix-coordinator); NAS exit and LAN routing. Enrollment and key expiry are managed in the admin console.";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.elem host hosts && config.services.tailscale.enable;
        message = "Fleet transport requires an enabled Tailscale daemon on one of the three tailnet hosts (client, nas, strix-coordinator); strix-worker stays off the tailnet (Tom, 2026-10-25).";
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
        assertion = router || builtins.elem "--exit-node=" preferences;
        message = "Only the NAS is an exit node and no host selects one (D-55 no-exit-client; Tom, 2026-10-25 \"default vanilla, make it work\").";
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
