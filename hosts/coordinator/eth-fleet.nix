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
#   - 10.99.0.0/30  tb-fleet   (thunderbolt0) — the fast rail, unchanged.
#   - 10.99.1.0/30  eth-fleet  (enp191s0)     — this file, always-on.
#   - 10.99.9.x/32  fleet IPs  (lo)           — the STABLE identity. Each
#     host routes to the peer's /32 twice: via TB at metric 50 (on the
#     tb-fleet profile, added imperatively like the profile itself) and
#     via ethernet at metric 200 (declared below). The kernel prefers TB
#     while thunderbolt0 exists, fails over the instant it vanishes, and
#     snaps back when tb-link-heal restores it. Connections to the fleet
#     IP survive the flip — the address never changes, only the path.
#
# Anything that must be TB-only (vLLM tensor traffic) still names
# 10.99.0.x explicitly; anything that must never die (SSH, healing,
# monitoring, deploys) names the fleet IP 10.99.9.2.
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
      # Peer fleet-IP fallback route, deliberately expensive (metric 200)
      # so the tb-fleet route (metric 50) always wins while it exists.
      routes = "10.99.9.2/32 10.99.1.2 200";
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
