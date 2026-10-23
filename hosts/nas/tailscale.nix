{ ... }:
{
  # The closet's only Tailscale node. Reuse the already enrolled nas-saas
  # identity from the retired container, never run both daemons over it.
  # Keep /var/lib/tailscale and /var/lib/headscale intact for rollback.
  services.tailscale = {
    enable = true;
    extraDaemonFlags = [ "--state=/var/lib/tailscale-personal/tailscaled.state" ];
    # Flags and routing features come from modules/fleet-transport.nix.
  };
  systemd.services.tailscaled = {
    conflicts = [ "container@nas-saas.service" ];
    after = [ "container@nas-saas.service" ];
    unitConfig.ConditionPathExists = "/var/lib/tailscale-personal/tailscaled.state";
  };
  # Never reset Serve/Funnel here: herdr-web-ui owns its declared listener.
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
