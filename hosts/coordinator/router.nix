{ ... }:
# The coordinator's LAN router plane. The TP-Link BE550 runs in AP mode (dumb
# layer-2 bridge + USB NAS); THIS box is the gateway, DHCP and DNS for the
# 10.42.0.0/24 wifi segment on enp191s0, with internet uplink over wifi
# (wlp192s0 → Freebox). Ported 2026-07-05 from the harness image
# (archive/harness/main mkosi.extra) + the live box's NM profile.
#
# DNS architecture: NM's shared-mode dnsmasq does DHCP ONLY (port=0) and
# advertises the gateway IP as resolver; AdGuard Home (rootless quadlet, see
# services.nix) owns :53; an nftables DNAT catches clients that hardcode
# 8.8.8.8; this host's own resolved also points at AdGuard. Tailscale MagicDNS
# keeps winning for *.ts.net via per-link DNS.
{
  # Gateway profile for the BE550 segment. ipv4.method=shared = NM runs dnsmasq
  # (DHCP+NAT) on this interface — same profile the Fedora box ran imperatively.
  networking.networkmanager.ensureProfiles.profiles.share-to-new = {
    connection = {
      id = "share-to-new";
      type = "ethernet";
      interface-name = "enp191s0";
      autoconnect = true;
    };
    ipv4 = {
      method = "shared";
      addresses = "10.42.0.1/24";
    };
    ipv6.method = "disabled";
  };

  environment.etc."NetworkManager/dnsmasq-shared.d/00-adguard.conf".text = ''
    # AdGuard owns :53 — NM's dnsmasq does DHCP only.
    port=0
    # DHCP option 6: hand BE550 wifi clients the gateway IP (= AdGuard) as resolver.
    dhcp-option=6,10.42.0.1
  '';

  environment.etc."NetworkManager/dnsmasq-shared.d/01-be550-pin.conf".text = ''
    # Pin the BE550's DHCP lease to 10.42.0.2 — /mnt/nas hardcodes it.
    # If the BE550 is ever replaced, find the new MAC with:
    #   ip neigh show dev enp191s0
    dhcp-host=98:03:8e:6b:61:e2,be550,10.42.0.2,infinite
  '';

  # Redirect :53 from clients that ignore DHCP option 6 (Chromecasts, IoT).
  # Own table, so the NixOS firewall's rules are untouched.
  networking.nftables = {
    enable = true;
    tables.dns_hijack = {
      family = "inet";
      content = ''
        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;
          ip daddr 10.42.0.1 return
          ip saddr 10.42.0.0/24 udp dport 53 dnat ip to 10.42.0.1
          ip saddr 10.42.0.0/24 tcp dport 53 dnat ip to 10.42.0.1
        }
      '';
    };
  };

  # This host's own DNS goes through AdGuard too (loopback reaches the
  # rootless container via its published 0.0.0.0:53).
  services.resolved.enable = true;
  environment.etc."systemd/resolved.conf.d/50-adguard.conf".text = ''
    [Resolve]
    DNS=127.0.0.1
  '';

  # LaCie 4TB, attached DIRECTLY to this box via USB (Tom's ruling 2026-07-05;
  # the old BE550-SMB path is retired). nofail + automount keep boot clean when
  # the drive is unplugged. The drive didn't enumerate at write time — if the
  # label differs, fix it from `lsblk -o LABEL,UUID` with the drive present.
  fileSystems."/mnt/nas" = {
    device = "/dev/disk/by-label/LaCie";
    fsType = "auto";
    options = [
      "uid=1000"
      "gid=100"
      "nofail"
      "noauto"
      "x-systemd.automount"
    ];
  };

  # AdGuard runs ROOTLESS (user quadlet) yet must bind :53.
  boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 53;

  # LAN DNS/DoT/AdGuard-admin + the app ports, reachable from the BE550 segment.
  networking.firewall.interfaces.enp191s0.allowedTCPPorts = [ 53 853 3000 8844 8443 2283 4533 ];
  networking.firewall.interfaces.enp191s0.allowedUDPPorts = [ 53 67 784 ];
}
