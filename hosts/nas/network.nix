{ ... }:
{
  # Keep the profile ID so NetworkManager updates the installed profile in place.
  networking.networkmanager.ensureProfiles.profiles.coordinator-fast-lane = {
    connection = {
      id = "coordinator-fast-lane";
      type = "ethernet";
      interface-name = "enp1s0";
      autoconnect = true;
      autoconnect-priority = 100;
    };
    ipv4 = {
      method = "manual";
      address1 = "10.42.0.1/24";
      gateway = "10.42.0.3";
      ignore-auto-dns = true;
    };
    ipv6.method = "disabled";
  };

  networking.hosts."10.42.0.2" = [ "coordinator" ];
  # The NAS reaches Immich ML over the LAN; the twins use their own fleet links.
  networking.hosts."10.42.0.5" = [ "worker" ];
  networking.nftables.enable = true;
  networking.firewall.extraInputRules = ''
    ip saddr 10.42.0.2 tcp dport 22 accept comment "coordinator SSH"
  '';
}
