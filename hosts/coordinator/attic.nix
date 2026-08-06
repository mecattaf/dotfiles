{
  config,
  lib,
  pkgs,
  ...
}:
# Fleet binary cache SERVER — atticd on the coordinator (conductor role, always-on).
# Built closures land here so every host can substitute them instead of repeating
# expensive source builds. Reachable over the Tailscale mesh, with no same-wifi
# requirement. refs #42.
#
# Gated on mySecrets.enable: atticd needs its RS256 JWT signing secret, delivered
# as an agenix EnvironmentFile (secrets/atticd-server-token.age, coordinator-only).
#
# sqlite + local storage under /var/lib/atticd (systemd StateDirectory) — no
# Postgres/object-store dependency; fine for this small fleet.
#
# RUNTIME BOOTSTRAP (once, after the first switch that brings atticd up):
#   1. Create the cache:   atticd-atticadm ... OR from a logged-in client:
#        attic login local http://coordinator:8080 "$(atticd-atticadm make-token \
#          --sub fleet-admin --validity '10y' --pull '*' --push '*' --create-cache '*')"
#        attic cache create fleet
#   2. Make it public so pulls need no per-client token/netrc:
#        attic cache configure fleet --public
#   3. Capture the cache's public signing key and append it to
#      modules/common.nix nix.settings.extra-trusted-public-keys:
#        attic cache info fleet     # → the `fleet:...=` public key line
#   4. Mint a push token for the coordinator builder and log it in (see common.nix).
{
  config = lib.mkIf config.mySecrets.enable {
    # RS256 JWT secret: EnvironmentFile with ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64
    # (generated `openssl genrsa -traditional 4096 | base64 -w0`). atticd signs and
    # validates all cache tokens with this key.
    age.secrets.atticd-server-token = {
      file = ../../secrets/atticd-server-token.age;
      # atticd runs as a DynamicUser; the module reads the EnvironmentFile as root
      # before dropping privileges, so root-readable (default 0400 owner root) is fine.
      mode = "400";
    };

    services.atticd = {
      enable = true;
      environmentFile = config.age.secrets.atticd-server-token.path;
      # monolithic: API server + GC + storage in one process (single-node fleet).
      mode = "monolithic";
      settings = {
        # Bind all interfaces; the firewall (below) restricts reachability to the
        # trusted mesh transports only — the same boundary used for wayvnc:5900.
        listen = "[::]:8080";
        # Let the substituter serve directly (clients hit /<cache>/nar/...); keep
        # the default sqlite DB + local storage under the atticd StateDirectory.

        # Retention bound (#133 doctrine: accumulating artifact, declared
        # policy; 2026-08-03 ruling: the cache STAYS on the coordinator, so it
        # must not be allowed to eat the NVMe toward its ~200G worst case).
        # Attic tracks last-accessed time, so this is keep-what-is-USED — a
        # closure the fleet still substitutes never expires; only paths nothing
        # has asked about in a month do. The staged hosts/nas/attic.nix
        # relocation remains the escape hatch if NVMe pressure returns.
        garbage-collection = {
          interval = "12 hours";
          default-retention-period = "1 month";
        };
      };
    };

    # Cache reachable over the two trusted transports only — never raw LAN/wifi.
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 8080 ];
    # The NAS is a substituter client like every other host (modules/common.nix
    # puts http://coordinator:8080/fleet in extra-substituters fleet-wide) but
    # has no tailnet identity, so it pulls over the private /30 cable. Losing
    # this would silently drop an 8 GB appliance back to building from source.
    # Scoped inside this mkIf on purpose: if the cache ever relocates to the NAS
    # (myNas.attic.enable + relayAttic, hosts/nas/attic.nix), atticd here goes
    # away and so does this rule — at which point the NAS serves 8080 rather
    # than dialing it, and the relay in nas-client.nix owns the tailnet door.
    networking.firewall.interfaces.enp191s0.allowedTCPPorts = [ 8080 ];

    # Cache-health tripwire. On 2026-07-26 the atticd DB was recreated
    # schema-only (cache record + server-side signing keypair lost) and the
    # fleet ran a whole week on 401s + cache.nixos.org fallback before anyone
    # noticed — pulls fail soft and the nightly push failure is a warning, so
    # nothing surfaced it. This probes what a client actually does: an
    # anonymous nix-cache-info fetch. Anything but 200 fires a marker into the
    # fleet-deploy channel (printed on interactive login).
    myTripwire.attic-cache-health = {
      description = "fleet binary cache answers anonymous pulls";
      intervalSeconds = 3600;
      onBootSec = "10min";
      threshold = 1;
      comparison = "ge";
      rearm = 0;
      # A persistent outage re-marks at most every 6h; recovery (a 200) re-arms.
      refractorySeconds = 21600;
      valueField = "CACHE_DOWN";
      sensorPath = [ pkgs.curl ];
      sensor = ''
        code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
          http://127.0.0.1:8080/fleet/nix-cache-info || echo 000)
        if [ "$code" = "200" ]; then
          echo "0 attic:fleet 1"
        else
          echo "1 attic:fleet 1"
        fi
      '';
      onFirePath = [ pkgs.coreutils ];
      onFire = ''
        mkdir -p /var/lib/fleet-deploy/failed
        printf '%s — fleet binary cache is not answering anonymous pulls (episode %s)\n  check: curl -s http://coordinator:8080/fleet/nix-cache-info ; journalctl -u atticd\n' \
          "$(date '+%Y-%m-%d %H:%M')" "$4" \
          > /var/lib/fleet-deploy/failed/attic-cache-health
      '';
    };
  };
}
