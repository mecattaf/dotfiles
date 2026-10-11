{ lib, ... }:
{
  # Strix binds its LAN address when software resolves gethostname(). A
  # second loopback answer is ambiguous; the NAS/client retain stock self pins.
  networking.hosts."127.0.0.2" = lib.mkForce [ ];
  networking.hosts."10.42.0.2" = [
    "strix"
    "coordinator"
  ];
  networking.hosts."10.42.0.16" = [ "client" ];
}
