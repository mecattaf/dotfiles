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

  networking.hosts."10.42.0.2" = [
    "strix"
    "coordinator"
  ];
  # The NAS reaches Immich ML over the LAN; the twins use their own fleet links.
  networking.nftables.enable = true;
  networking.firewall.extraInputRules = ''
    ip saddr 10.42.0.2 tcp dport 22 accept comment "strix SSH"
  '';

  # 2026-10-25: the SN7100 in the second M.2 moved the AQC113 (atlantic, ec:1a:c3:04:9d:54)
  # from PCI 01:00.0 to 02:00.0; udev named it enp2s0 and orphaned every enp1s0-bound
  # router setting. Pin the LAN name by permanent MAC (T-51). Deliberately NOT named
  # "10-nas-lan": the imperative /etc/systemd/network/10-nas-lan.link must stay an
  # unmanaged regular file until a generation with this link is the boot default and has
  # been reboot-proven, because booting a generation without this link deletes its static
  # symlink (setup-etc cleanup).
  systemd.network.links."10-lan" = {
    matchConfig.PermanentMACAddress = "ec:1a:c3:04:9d:54";
    linkConfig.Name = "enp1s0";
  };
}
