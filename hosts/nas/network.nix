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

  # 2026-10-25: the SN7100 in the second M.2 moved the AQC113 (atlantic,
  # ec:1a:c3:04:9d:54) from PCI 01:00.0 to 02:00.0; udev named it enp2s0 and
  # orphaned every enp1s0-bound router setting (the profile above, dnsmasq,
  # the firewall). Pin the LAN name by permanent MAC (T-51).
  #
  # Deliberately NOT named "10-nas-lan": that is the imperative regular file
  # /etc/systemd/network/10-nas-lan.link written during the outage. NixOS
  # setup-etc replaces a regular file with its /etc/static symlink, and booting
  # any older generation then deletes that symlink as obsolete, which would
  # recreate the outage. Under its own name the imperative file survives every
  # generation; it is removed only after a generation with this link is the
  # boot default and has been reboot-proven (D-52). Both files sort before
  # 99-default.link and say the same thing.
  systemd.network.links."10-lan" = {
    matchConfig.PermanentMACAddress = "ec:1a:c3:04:9d:54";
    linkConfig.Name = "enp1s0";
  };

  # The NAS reaches Immich ML over the LAN; the twins use their own fleet links.
  networking.nftables.enable = true;
  networking.firewall.extraInputRules = ''
    ip saddr 10.42.0.16 tcp dport 22 accept comment "Zenbook SSH"
    ip saddr 10.42.0.16 tcp dport 27321 accept comment "Zenbook Atuin"
    ip saddr 10.42.0.2 tcp dport 22 accept comment "strix SSH"
  '';
}
