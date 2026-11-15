{ ... }:
{
  # The fleet's only exit node and subnet router. Reuse the already enrolled
  # nas-saas identity from the retired container, never run both daemons over it.
  # Keep /var/lib/tailscale and /var/lib/headscale intact for rollback.
  services.tailscale = {
    enable = true;
    # tailscaled derives its state directory from --state only when the parent
    # is named "tailscale"; without --statedir it has nowhere for Serve's TLS
    # certificates ("no TailscaleVarRoot") and herdr-web-ui's HTTPS fails.
    extraDaemonFlags = [
      "--state=/var/lib/tailscale-personal/tailscaled.state"
      "--statedir=/var/lib/tailscale-personal"
    ];
    # Flags and routing features come from modules/fleet-transport.nix.
  };
  systemd.services.tailscaled = {
    conflicts = [ "container@nas-saas.service" ];
    after = [ "container@nas-saas.service" ];
    unitConfig.ConditionPathExists = "/var/lib/tailscale-personal/tailscaled.state";
  };
  # Never reset Serve/Funnel here: herdr-web-ui owns its declared listener.
  # Academic drain's read-only master-index page owns ONLY /drain/ on the
  # existing background :8444 listener. The root :8444 proxy and Herdr's
  # foreground :443 listener are separate and must stay intact.
  # Bootstrap once (Serve --bg persists in the existing tailscaled state):
  #   tailscale serve --bg --https=8444 --set-path=/drain /var/lib/academic-drain-web
  # The existing checkpoint renderer writes just index.html here. No server,
  # generator timer, new agent harness or boot-time Serve reset is needed.
  systemd.tmpfiles.rules = [
    "d /var/lib/academic-drain-web 0700 tom users -"
  ];
  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [
      22
      53
      2283
      4533
      32400
    ];
    allowedUDPPorts = [ 53 ];
  };
}
