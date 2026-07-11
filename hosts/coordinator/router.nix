{ config, lib, ... }:
let
  # The Freebox uplink PSK ships as an agenix secret (secrets/wifi.age). Until
  # that ciphertext is committed the whole declarative-wifi block stays inert so
  # nothing here can break eval or clobber the live imperative connection.
  wifiReady = builtins.pathExists ../../secrets/wifi.age;
in
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

  # Internet uplink: the Freebox AP over wifi (wlp192s0). Ported from the live
  # imperative NM profile that was hand-copied off the worker on flash night
  # (refs #37); field-for-field mirror of `nmcli connection show Freebox-AB3ACE`
  # (2026-07-11), minus the PSK, which comes from secrets/wifi.age via
  # `environmentFiles` `$FREEBOX_PSK` substitution. Both halves are gated on
  # `wifiReady` so this never lands a half-substituted profile that would fight
  # the live connection.
  networking.networkmanager.ensureProfiles.profiles.freebox-uplink =
    lib.mkIf wifiReady {
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
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk = "$FREEBOX_PSK";
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
  networking.networkmanager.ensureProfiles.environmentFiles =
    lib.mkIf wifiReady [ config.age.secrets.wifi.path ];

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

  # AdGuard serves the BE550 wifi clients ONLY (Tom's ruling 2026-07-05 flash
  # night: "ad-free internet for devices like my phone, nothing else"). This
  # host resolves through its normal uplink DNS (Freebox via wifi DHCP) — the
  # original port wrongly chained the host's own lookups to AdGuard, which made
  # coordinator DNS dead until the AdGuard wizard ran.
  # DNSStubListener stays off: resolved's stubs (127.0.0.53/54:53) hold the
  # port and AdGuard's wildcard 0.0.0.0:53 bind gets EADDRINUSE — found as a
  # crashloop on first NixOS boot. Host lookups go via nss-resolve → resolved
  # → link DNS, so MagicDNS keeps working.
  services.resolved.enable = true;
  environment.etc."systemd/resolved.conf.d/50-adguard.conf".text = ''
    [Resolve]
    DNSStubListener=no
  '';

  # LaCie 4TB, attached DIRECTLY to this box via USB (Tom's ruling 2026-07-05;
  # the old BE550-SMB path is retired). nofail + automount keep boot clean when
  # the drive is unplugged. Label/device confirmed live 2026-07-11:
  # `lsblk -f` → sda2, LABEL=LaCie, NTFS. The old `fsType = "auto"` failed every
  # boot because no NTFS driver was configured; the in-kernel ntfs3 driver
  # (mature on kernel 7.1, built in — `ntfs3` in /proc/filesystems) mounts it
  # natively with no ntfs-3g/FUSE dependency. uid/gid are honoured by ntfs3.
  fileSystems."/mnt/nas" = {
    device = "/dev/disk/by-label/LaCie";
    fsType = "ntfs3";
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
