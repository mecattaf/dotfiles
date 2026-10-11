{ ... }:
{
  # Shell-history sync remains strix-local when the media core moves.
  services.atuin = {
    enable = true;
    host = "0.0.0.0";
    port = 27321;
    openRegistration = true;
  };
  networking.firewall.interfaces.enp191s0.allowedTCPPorts = [ 27321 ];
}
