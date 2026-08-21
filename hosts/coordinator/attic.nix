{
  config,
  lib,
  pkgs,
  ...
}:
# Fleet binary cache — SERVED FROM THE NAS since 2026-08-21 (ws5 executed;
# hosts/nas/attic.nix has the story and the runbook). This file used to run
# atticd here; what remains on the coordinator is:
#
#   1. NOTHING server-shaped. atticd is off; the RS256 secret is no longer
#      delivered here (the NAS holds it as a runbook-placed file). The old
#      /var/lib/atticd stays on disk as the ROLLBACK COPY until the first
#      healthy week after the move, then gets deleted by hand.
#   2. The cache-health tripwire, retained and repointed at the NAS: the
#      2026-07-26 silent-loss incident (schema-only DB, a week of 401s
#      nobody saw) is exactly as possible on the new host, and this box is
#      still the fleet's watchtower.
{
  # Probes what a client actually does: an anonymous nix-cache-info fetch
  # against the real substituter URL. Anything but 200 fires a marker into
  # the failure-marker channel (printed on interactive login).
  myTripwire.attic-cache-health = {
    description = "fleet binary cache (on the NAS) answers anonymous pulls";
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
        http://nas:8080/fleet/nix-cache-info || echo 000)
      if [ "$code" = "200" ]; then
        echo "0 attic:fleet 1"
      else
        echo "1 attic:fleet 1"
      fi
    '';
    onFirePath = [ pkgs.coreutils ];
    onFire = ''
      mkdir -p /var/lib/failure-markers
      printf '%s — fleet binary cache is not answering anonymous pulls (episode %s)\n  check: curl -s http://nas:8080/fleet/nix-cache-info ; ssh nas journalctl -u atticd\n' \
        "$(date '+%Y-%m-%d %H:%M')" "$4" \
        > /var/lib/failure-markers/attic-cache-health
    '';
  };
}
