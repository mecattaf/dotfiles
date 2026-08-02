{ ... }:
{
  # One cable, one fixed private fast lane. enp1s0 is the live predictable
  # name of the sole onboard NIC (Aquantia AQC113 10GbE at PCI 01:00.0),
  # recorded in the kexec installer 2026-08-01.
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
      address1 = "10.77.0.2/30";
      gateway = "10.77.0.1";
      dns = "1.1.1.1;9.9.9.9;";
      ignore-auto-dns = true;
    };
    ipv6.method = "ignore";
  };

  networking.hosts."10.77.0.1" = [ "coordinator" ];

  # extraInputRules is an nftables-only option: under the default iptables
  # backend it renders NOTHING and the rules below silently vanish. That
  # sealed the first installed system shut (SSH dropped, ping-only; recovered
  # via the tty1 autologin getty on 2026-08-01). The nas-topology flake check
  # now asserts this stays on.
  networking.nftables.enable = true;

  # The coordinator is the only peer and supplies every routed/relayed path.
  networking.firewall.extraInputRules = ''
    ip saddr 10.77.0.1 tcp dport 22 accept comment "coordinator SSH over private NAS link"
  '';
}
