{ pkgs, ... }:
{
  # Observe the direction that failed in #514: client -> Strix. Avoid treating
  # a travelling/offline laptop as a closet outage. Never repair/restart Herdr.
  myTripwire.strix-reachability = {
    description = "Strix SSH is reachable from the client";
    intervalSeconds = 30;
    onBootSec = "2min";
    threshold = 1;
    comparison = "ge";
    sustainSeconds = 90;
    rearm = 1;
    valueField = "STRIX_UNREACHABLE";
    sensorPath = [
      pkgs.iproute2
      pkgs.jq
      pkgs.netcat-openbsd
      pkgs.coreutils
    ];
    sensor = ''
      if ! ip -json route get 10.42.0.2 2>/dev/null | jq -e \
        'any(.[]; .dev == "tailscale0" or .prefsrc == "10.42.0.16")' >/dev/null; then
        echo "0 offline 1"
      elif nc -z -w 3 10.42.0.2 22; then
        rm -f /var/lib/failure-markers/strix-reachability
        echo "0 strix 1"
      else
        echo "1 strix 1"
      fi
    '';
    onFirePath = [ pkgs.coreutils ];
    onFire = ''
      mkdir -p /var/lib/failure-markers
      printf '%s — Strix SSH (10.42.0.2:22) unreachable from this client for 90 seconds (episode %s). Check Ethernet, BE550 and Strix power.\n' \
        "$(date '+%Y-%m-%d %H:%M')" "$4" > /var/lib/failure-markers/strix-reachability
    '';
  };
}
