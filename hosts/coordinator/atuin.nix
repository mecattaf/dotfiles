{ ... }:
{
  # Shell-history sync remains coordinator-local when the media core moves.
  services.atuin = {
    enable = true;
    host = "0.0.0.0";
    port = 27321;
    openRegistration = true;
  };
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 27321 ];
}
