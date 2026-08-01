{ ... }:
{
  # One cable, one fixed private fast lane. Omitting interface-name is
  # deliberate until the live hardware config records UGREEN's NIC name; this
  # is the only physical Ethernet profile on the appliance.
  networking.networkmanager.ensureProfiles.profiles.coordinator-fast-lane = {
    connection = {
      id = "coordinator-fast-lane";
      type = "ethernet";
      autoconnect = true;
      autoconnect-priority = 100;
    };
    ipv4 = {
      method = "manual";
      address1 = "10.77.0.2/30";
      gateway = "10.77.0.1";
      dns = "1.1.1.1;9.9.9.9;";
      ignore-auto-dns = true;
    };
    ipv6.method = "ignore";
  };

  networking.hosts."10.77.0.1" = [ "coordinator" ];

  # The coordinator is the only peer and supplies every routed/relayed path.
  networking.firewall.extraInputRules = ''
    ip saddr 10.77.0.1 tcp dport 22 accept comment "coordinator SSH over private NAS link"
  '';
}
