{ ... }:
{
  # Clients use .1 for gateway + DNS. The NAS filters and returns internet
  # traffic through the same Ethernet port to BE550 .3, whose WAN is Freebox.
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.enp1s0.send_redirects" = 0;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.enp1s0.accept_redirects" = 0;
  };

  services.dnsmasq = {
    enable = true;
    settings = {
      port = 0; # DHCP only; AdGuard owns DNS.
      interface = "enp1s0";
      bind-dynamic = true;
      dhcp-range = "10.42.0.10,10.42.0.200,255.255.255.0,12h";
      dhcp-option = [
        "option:router,10.42.0.1"
        "option:dns-server,10.42.0.1"
      ];
      dhcp-authoritative = true;
      # The worker is pinned on its WIRED 5GbE NIC (enp191s0), which is its
      # only link to the house since 2026-09-11. The earlier pin named the
      # box's idle wifi MAC (44:f7:9f:da:bd:1d) — a radio that never
      # associates, so the reservation could never match. The host also
      # configures .5 statically (hosts/worker/default.nix), and .5 sits
      # below the pool (.10-.200); this pin keeps the address reserved so
      # nothing else can be handed it and the name stays stable.
      dhcp-host = [
        "ac:f2:3c:35:1e:d1,coordinator,10.42.0.2,infinite"
        "98:03:8e:6b:61:e2,be550,10.42.0.3,infinite"
        "08:f9:7e:55:f3:96,printer,10.42.0.4,infinite"
        "9c:bf:0d:01:cc:65,worker,10.42.0.5,infinite"
        # The thin client (2026-09-11): the lease it already held on return
        # day, made permanent so the registry alias and the twins' /etc/hosts
        # line (modules/fleet-hosts.nix) stay true. Inside the pool on
        # purpose — a dhcp-host reservation withdraws the address from
        # dynamic allocation, and moving the box would have meant touching
        # its profile on the day it came back.
        "a0:b3:39:06:75:a7,client,10.42.0.16,infinite"
      ];
    };
  };

  networking.firewall.extraInputRules = ''
    iifname "enp1s0" udp dport 67 accept comment "LAN DHCP"
    iifname "enp1s0" udp dport 53 accept comment "LAN AdGuard"
    iifname "enp1s0" tcp dport 53 accept comment "LAN AdGuard TCP"
  '';

  # Source NAT makes BE550 send replies back through the NAS. LAN traffic and
  # Tailscale forwarding retain their original paths and identities.
  networking.nftables.tables.nas_upstream = {
    family = "ip";
    content = ''
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        iifname "enp1s0" oifname "enp1s0" ip saddr 10.42.0.0/24 ip daddr != 10.42.0.0/24 counter snat to 10.42.0.1
      }
    '';
  };

  # These rules apply to clients routed through the NAS. Selecting BE550 .3
  # directly is an accepted bypass. NAS-originated upstream DNS is unaffected.
  networking.nftables.tables.dns_hijack = {
    family = "inet";
    content = ''
      chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        iifname != "enp1s0" return
        ip daddr 10.42.0.1 return
        ip saddr 10.42.0.0/24 udp dport 53 dnat ip to 10.42.0.1
        ip saddr 10.42.0.0/24 tcp dport 53 dnat ip to 10.42.0.1
      }
      chain forward {
        type filter hook forward priority filter; policy accept;
        iifname "enp1s0" ip saddr 10.42.0.0/24 tcp dport 853 drop
        iifname "enp1s0" ip saddr 10.42.0.0/24 ip daddr {
          8.8.8.8, 8.8.4.4,
          1.1.1.1, 1.0.0.1,
          9.9.9.9, 149.112.112.112,
          208.67.222.222, 208.67.220.220
        } tcp dport 443 drop
      }
    '';
  };
}
