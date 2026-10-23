{ config, lib, ... }:
{
  # Pin self resolution to the wired LAN on compute. Preserve the stock
  # loopback self pins for the NAS and the mobile physical seat.
  networking.hosts = {
    "10.42.0.1" = [ "nas" ];
    "10.42.0.2" = [
      "strix-coordinator"
      "strix"
    ]; # temporary old-name alias
    "10.42.0.5" = [ "strix-worker" ];
    "10.42.0.16" = [ "client" ];
  }
  // lib.optionalAttrs (config.myFleet.has "compute") {
    "127.0.0.2" = lib.mkForce [ ];
  };
}
