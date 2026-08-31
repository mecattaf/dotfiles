{ pkgs, ... }:
# ─── eth-fleet: the wired fallback rail under tb-fleet ──────────────────────
#
# Born the same night as the CCGx doctrine (2026-08-21, see ./tb-fleet.nix):
# the Thunderbolt link's entire failure class lives in the USB-C/PD stack,
# and Tom is about to run deliberate USB4 experiments (ds4-vllm) on top of
# it. The answer is a second, boring rail that shares NOTHING with USB-C:
# the 5GbE port (enp191s0, idle since install) cabled directly to the
# worker's twin port. Different controller, different PHY, no CCGx — the
# management path survives anything the TB side does.
#
# Addressing doctrine, three layers:
#   - 10.99.0.0/30  tb-fleet   (thunderbolt0) — the tensor rail, unchanged.
#   - 10.99.1.0/30  eth-fleet  (enp191s0)     — this file, always-on.
#   - 10.99.9.x/32  fleet IPs  (lo)           — the STABLE identity. Each
#     host routes to the peer's /32 twice: via ethernet at metric 20
#     (declared below) and via TB at metric 50 (on the tb-fleet profile,
#     added imperatively like the profile itself). The kernel prefers the
#     wire while enp191s0 exists, fails over to TB the instant it
#     vanishes, and snaps back when the cable returns. Connections to the
#     fleet IP survive the flip — the address never changes, only the path.
#
#     METRICS FLIPPED 2026-08-28 (dotfiles#240 ruling): ethernet used to sit
#     at 200 behind TB's 50, which meant admin traffic on the fleet IP rode
#     Thunderbolt whenever it was up — a `reboot` sharing the rail being
#     tuned for vLLM tensor traffic (#238) and owning the fleet's whole
#     USB-C/PD failure class. Now TB is the fleet IP's FAILOVER, never its
#     preference. The imperative TB route stays at 50, untouched — only
#     this profile's declared metric moved below it.
#
# Anything that must be TB-only (vLLM tensor traffic) still names
# 10.99.0.x explicitly; anything that must never die (SSH, healing,
# monitoring, deploys) names the fleet IP 10.99.9.2 and since #240
# thereby prefers the wire.
#
# The tb-fleet-reachability tripwire deliberately keeps pinging 10.99.0.2:
# it watches the FAST rail specifically. This rail gets its own quieter
# tripwire below — if BOTH rails are ever dark, both fire and the marker
# text says so.
{
  # The stable /32 fleet identity, on loopback so it exists independent of
  # either physical rail. A dedicated oneshot because networking.localCommands
  # is masked under NetworkManager (found the hard way on deploy night).
  systemd.services.fleet-identity = {
    description = "Stable fleet identity 10.99.9.1/32 on loopback";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-pre.target" ];
    # Since #273 the hostname resolves to this /32, so any service that binds
    # by hostname needs the address on lo FIRST. after=network-pre alone gave
    # no such guarantee (review finding 2026-08-31): nothing ordered this
    # before the binders. before=network.target does — the conventional edge
    # for "network identity is set up" — and binders are After=network.target
    # by convention. A unit that binds the hostname EARLIER than that now
    # fails loudly instead of binding loopback quietly: the intended trade.
    before = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.iproute2}/bin/ip addr replace 10.99.9.1/32 dev lo";
    };
  };

  networking.networkmanager.ensureProfiles.profiles.eth-fleet = {
    connection = {
      id = "eth-fleet";
      type = "ethernet";
      interface-name = "enp191s0";
      autoconnect = true;
      # Below every uplink: this profile must never be NM's idea of a
      # default route or DNS source.
      autoconnect-priority = 50;
    };
    ipv4 = {
      method = "manual";
      addresses = "10.99.1.1/30";
      never-default = true;
      ignore-auto-dns = true;
      # Peer fleet-IP route, deliberately CHEAP (metric 20) so it beats the
      # imperative tb-fleet route (metric 50) whenever the wire is up — the
      # #240 flip; TB is the failover now, see the header. Keyfile syntax
      # (routeN=dest,next-hop,metric) — a nmcli-style `routes` key is
      # silently ignored by the keyfile parser.
      route1 = "10.99.9.2/32,10.99.1.2,20";
    };
    ipv6.method = "disabled";
  };

  networking.firewall.trustedInterfaces = [ "enp191s0" ];

  # The quieter tripwire promised above: a dead FALLBACK rail costs nothing
  # today and everything during the next TB incident, so its darkness must
  # still surface — just on a slower clock than the fast rail's (checked
  # every 15 min, fires after ~1 h dark, 12 h refractory).
  myTripwire.eth-fleet-reachability = {
    description = "the worker answers pings over the 5GbE fallback /30";
    intervalSeconds = 900;
    onBootSec = "15min";
    threshold = 1;
    comparison = "ge";
    sustainSeconds = 3600;
    rearm = 0;
    refractorySeconds = 43200;
    valueField = "ETH_DARK";
    sensorPath = [ pkgs.iputils ];
    sensor = ''
      if ping -c 2 -W 3 10.99.1.2 >/dev/null 2>&1; then
        echo "0 eth 1"
      else
        echo "1 eth 1"
      fi
    '';
    onFirePath = [ pkgs.coreutils ];
    onFire = ''
      mkdir -p /var/lib/failure-markers
      printf '%s — the worker has not answered on the 5GbE fallback rail for ~1 h (episode %s)\n  The TB rail may still be fine; this marker means the SAFETY NET is gone: check the cable in both rear 5GbE ports and run "nmcli connection up eth-fleet" on both ends (see hosts/coordinator/eth-fleet.nix)\n' \
        "$(date '+%Y-%m-%d %H:%M')" "$4" \
        > /var/lib/failure-markers/eth-fleet-reachability
    '';
  };
}
