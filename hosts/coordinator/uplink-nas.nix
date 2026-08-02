{
  config,
  lib,
  ...
}:
let
  # The Freebox uplink PSK ships as an agenix secret (secrets/wifi.age). Until
  # that ciphertext is committed the whole declarative-wifi block stays inert so
  # nothing here can break eval or clobber the live imperative connection.
  wifiReady = builtins.pathExists ../../secrets/wifi.age;
in
# The coordinator's internet uplink + directly-attached NAS.
#
# HISTORY: this file was `router.nix` and made the coordinator a LAN gateway /
# DHCP / DNS server for a downstream 10.42.0.0/24 wifi segment on enp191s0,
# fronted by a TP-Link BE550 in AP mode. The BE550 was RETIRED 2026-07-13 and
# physically unplugged, so that entire router plane is gone — the shared-mode
# gateway profile, the dnsmasq-shared DHCP drop-ins, the BE550 lease pin, the
# nftables :53 DNAT + encrypted-DNS-bypass drops, the enp191s0 firewall holes,
# and the DNSStubListener=no hack that only existed so the old rootless AdGuard
# quadlet could own :53 for those wifi clients. DNS filtering now lives per-box
# in modules/adguardhome.nix (loopback resolver) instead of a LAN service here.
#
# What remains is genuinely BE550-independent:
#   - the Freebox wifi uplink (wlp192s0), this box's actual internet, and
#   - a private routed fast lane to the headless NixOS host `nas`.
#
# The LaCie 4TB USB plane that used to live here (the /mnt/nas automount, the
# SAT smartd thermal watch, the hd-idle spin-down suite) was RETIRED 2026-08-02
# with the NAS cutover (#131): the real NAS owns /mnt/nas now, the LaCie hangs
# off the NAS as the rollback copy, and if it ever mounts anywhere again the
# path is /mnt/lacie — never /mnt/nas — with no monitoring attached. See git
# history for the retired blocks (they carried the probed USB-bridge lore:
# `-n standby,q`, `-c ata`, kernel-name resolution for hd-idle).
{
  # Internet uplink: the Freebox AP over wifi (wlp192s0). Ported from the live
  # imperative NM profile that was hand-copied during flash night
  # (refs #37); field-for-field mirror of `nmcli connection show Freebox-AB3ACE`
  # (2026-07-11), minus the PSK, which comes from secrets/wifi.age via
  # `environmentFiles` `$FREEBOX_PSK` substitution. Both halves are gated on
  # `wifiReady` so this never lands a half-substituted profile that would fight
  # the live connection.
  networking.networkmanager.ensureProfiles.profiles.freebox-uplink = lib.mkIf wifiReady {
    connection = {
      id = "Freebox-AB3ACE";
      type = "wifi";
      interface-name = "wlp192s0";
      autoconnect = true;
      autoconnect-priority = 100;
    };
    wifi = {
      mode = "infrastructure";
      ssid = "Freebox-AB3ACE";
      # Pinned HARD to the Freebox's 5GHz radio (2026-07-16). The mt7925e
      # driver has a wcid list-corruption race on the same-SSID band-steering
      # roam path (2.4↔5GHz hop): `list_add corruption` → `kernel BUG at
      # lib/list_debug.c:32` inside a locked section → instant full lockup,
      # no oops, no video, no network, power-cycle required. It killed this
      # box TWICE in 12h (boots ending 2026-07-16 01:06 and 13:17, journal
      # -2/-1), both times at the exact instant of a roam to this BSSID.
      # Kernel 7.1 already carries the known upstream fixes for this bug
      # class (double-wcid-init + wcid_cleanup poll_list, verified in-tree),
      # so this is a remaining unfixed race; BIOS 3.05 (2026-07-14) armed it:
      # 11 roams / 8 days / 0 crashes on 3.02 vs 9 roams / 2 crashes on 3.05.
      # No roam, no crash. Trade-off: no 2.4GHz fallback if the 5GHz radio
      # drops — fine for a stationary desktop; see also the disable_aspm +
      # watchdog hardening in modules/strix.nix.
      bssid = "8C:97:EA:FE:FA:E0";
      band = "a";
    };
    wifi-security = {
      key-mgmt = "wpa-psk";
      psk = "$FREEBOX_PSK";
    };
    ipv4.method = "auto";
    ipv6.method = "auto";
  };
  networking.networkmanager.ensureProfiles.environmentFiles = lib.mkIf wifiReady [
    config.age.secrets.wifi.path
  ];

  # Dedicated point-to-point link to the new NAS. This deliberately follows the
  # proven wired-speaker arrangement: NetworkManager owns and raises the NIC,
  # dnsmasq is DHCP-only for factory/installer boots, the /30 is trusted, and
  # NAT relays the appliance to the internet through the coordinator's wifi.
  networking.networkmanager.ensureProfiles.profiles.nas-fast-lane = {
    connection = {
      id = "nas-fast-lane";
      type = "ethernet";
      interface-name = "enp191s0";
      autoconnect = true;
      autoconnect-priority = 50;
    };
    ipv4 = {
      method = "manual";
      address1 = "10.77.0.1/30";
      never-default = true;
    };
    ipv6.method = "ignore";
  };

  # One downstream lease on the only other usable address. Once NixOS is
  # installed it uses the same address statically, so canonical routing never
  # depends on DHCP. port=0 prevents any collision with loopback AdGuard :53.
  services.dnsmasq = {
    enable = true;
    settings = {
      port = 0;
      interface = "enp191s0";
      bind-dynamic = true;
      dhcp-range = "10.77.0.2,10.77.0.2,255.255.255.252,12h";
      dhcp-option = [
        "option:router,10.77.0.1"
        "option:dns-server,1.1.1.1,9.9.9.9"
      ];
      dhcp-authoritative = true;
    };
  };

  networking.nat = {
    enable = true;
    internalInterfaces = [ "enp191s0" ];
    externalInterface = "wlp192s0";
  };
  networking.firewall.trustedInterfaces = [ "enp191s0" ];
  networking.hosts."10.77.0.2" = [ "nas" ];
}
