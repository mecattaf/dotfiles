{ config, lib, ... }:
lib.mkIf (config.myFleet.has "brain") {
  services.atuin = {
    enable = true;
    host = "0.0.0.0";
    port = 27321;
    openRegistration = true;
  };
  # NAS admits the Zenbook on LAN in hosts/nas/network.nix and tailnet here.
  # Keep the pre-cutover strix listener until the compute-host PR removes brain.
  networking.firewall.interfaces =
    if config.myFleet.has "router" then
      {
        tailscale0.allowedTCPPorts = [ 27321 ];
      }
    else
      {
        enp191s0.allowedTCPPorts = [ 27321 ];
      };
}
