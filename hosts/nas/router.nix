{
  config,
  lib,
  pkgs,
  ...
}:
let
  a8500 = import ./a8500.nix;
  a8500Known = a8500.mac != null;
in
# The NAS's router plane (2026-08-20 cutover): this box ingests the Freebox
# wifi on a Netgear A8500 USB adapter ("wan0") and is gateway, DHCP and DNS
# for the 10.42.0.0/24 LAN on enp1s0, fronted by the TP-Link Archer BE550 in
# AP mode at the TV corner. The plane is a port of the coordinator's retired
# router.nix (recovered via `git show 26d4afdf^:hosts/coordinator/router.nix`)
# — same segment number, same BE550, same DNS-hijack doctrine — with three
# deliberate differences:
#
#   - the wifi *client* half lives here (the BE550's stock firmware has no
#     WISP/repeater mode, and the NAS has no radio of its own — the A8500 is
#     the listening ear both lack);
#   - AdGuard is the NixOS service from modules/adguardhome.nix serving the
#     whole LAN (bind + boot-race handling live there), not a rootless
#     quadlet, so no ip_unprivileged_port_start sysctl and no
#     DNSStubListener hack;
#   - firewall admissions use this box's nftables extraInputRules idiom
#     (hosts/nas/network.nix:26-31 records why), not
#     interfaces.<if>.allowedTCPPorts.
#
# TRANSITIONAL (dual-rail) until the /30 cleanup commit: the LAN address
# coexists with the old /30 on enp1s0 (hosts/nas/network.nix), so the
# physical move from the coordinator's cable to the BE550's switch changes
# no addressing at all — only which wire carries it.
{
  # ── wan0: deterministic name for the A8500 ────────────────────────────────
  # USB wifi otherwise enumerates as wlx<mac>, and networking.nat needs a
  # literal externalInterface. Match the permanent MAC (facts file), name it
  # wan0. Inert while a8500.nix is null.
  systemd.network.links."10-wan0" = lib.mkIf a8500Known {
    matchConfig.PermanentMACAddress = a8500.mac;
    linkConfig.Name = "wan0";
  };

  # a8500-new-id shim RETIRED 2026-08-29, exactly as its own header promised:
  # the A8500's USB ID is in the stock mt7925u table from kernel 7.2, and
  # ./kernel.nix put this box on the 7.2 series in the same commit. One
  # correction to the original "delete with a8500.nix's usb fields" note:
  # the VID/PID fields STAY — they grew two load-bearing consumers after
  # that note was written (wan-watchdog.nix's rung-3 USB re-enumeration and
  # the udev power rule below). Only the shim service goes. Safe on a live
  # switch: the running 7.1.x kernel keeps its already-written new_id entry
  # until the module unloads, and the reboot that drops it boots 7.2.

  # ── USB power management OFF for the uplink radio (2026-08-21) ────────────
  # Two distinct doze mechanisms can add 100-400ms wake latency to this
  # radio, and a house router's uplink must never doze:
  #   1. 802.11 power-save — the mt76 SOFTWARE power-save pathology (the
  #      driver disables it for USB mt7925u since Dec 2023, but the
  #      supplicant/NM layer can still request it) → wifi.powersave = 2 on
  #      the freebox-uplink profile below. Diagnosed live: 114-370ms idle
  #      RTT before, ~15ms after.
  #   2. USB autosuspend — the USB core suspending the whole device link,
  #      independent of 802.11 PS. Mains-powered always-on box: no upside.
  #      Kernel param covers boot; the scoped udev rule is the per-device
  #      belt-and-suspenders (applies on enumeration).
  boot.kernelParams = [ "usbcore.autosuspend=-1" ];
  services.udev.extraRules = lib.mkIf (a8500Known && a8500.usbVid != null) ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="${a8500.usbVid}", ATTR{idProduct}=="${a8500.usbPid}", TEST=="power/control", ATTR{power/control}="on"
  '';

  # ── Internet uplink: the Freebox AP over the A8500 ───────────────────────
  # Field-for-field port of the coordinator's freebox-uplink profile
  # (hosts/coordinator/uplink-nas.nix), including the 5GHz BSSID pin: the
  # mt7925 family's same-SSID band-steering roam is the crash class that
  # hard-locked the coordinator twice on 2026-07-16 (wcid list corruption;
  # full lore at uplink-nas.nix:54-70). mt7925u shares that core; a
  # stationary appliance that is now the HOUSE ROUTER gets the same "no roam,
  # no crash" treatment. No interface-name: this box has exactly one radio.
  #
  # The PSK is a runbook-placed root file, NOT agenix: the NAS is
  # deliberately off the delivered secrets tier (secrets.nix:27-34, decision
  # reaffirmed for the attic move at hosts/nas/attic.nix:14-19). Place it
  # once, before the phase-1 deploy:
  #   install -d -m 700 /var/lib/nas-router
  #   printf 'FREEBOX_PSK=<psk>\n' > /var/lib/nas-router/freebox-uplink.env
  #   chmod 600 /var/lib/nas-router/freebox-uplink.env
  networking.networkmanager.ensureProfiles.profiles.freebox-uplink = {
    connection = {
      id = "Freebox-AB3ACE";
      type = "wifi";
      autoconnect = true;
      autoconnect-priority = 100;
    };
    wifi = {
      mode = "infrastructure";
      ssid = "Freebox-AB3ACE";
      bssid = "8C:97:EA:FE:FA:E0";
      band = "a";
      # The router's WAN identity must be stable for the Freebox's DHCP
      # lease; NM's default MAC handling randomized the scan address on
      # first plug-in (seen live: e2:d5:2b:...), so pin the association to
      # the permanent MAC explicitly.
      cloned-mac-address = "permanent";
      # Wifi power-save OFF (2 = disable; NM default let the mt7925u doze).
      # Diagnosed live 2026-08-21: idle-inbound RTT to this radio was
      # 114-370ms (classic power-save wake latency) while NAS-originated
      # traffic ran at 1-2ms; a house ROUTER's uplink must never doze.
      # Applied at runtime the same day (nmcli modify + connection bounce:
      # 227ms avg -> 15ms avg from a Freebox-side client).
      powersave = 2;
    };
    wifi-security = {
      key-mgmt = "wpa-psk";
      psk = "$FREEBOX_PSK";
    };
    ipv4.method = "auto";
    # v4-only plane, like the retired coordinator plane: no RA/NAT66 story on
    # the LAN, so don't accept a v6 default route on the uplink either.
    ipv6.method = "ignore";
  };
  networking.networkmanager.ensureProfiles.environmentFiles = [
    "/var/lib/nas-router/freebox-uplink.env"
  ];

  # ── NAT: the LAN's internet ──────────────────────────────────────────────
  # Renders into nixos-filter-forward exactly like the coordinator's retired
  # arrangement did for the /30. With a8500.nix still null there is no wan0
  # link; an nftables rule naming a nonexistent iface simply never matches.
  networking.nat = {
    enable = true;
    internalInterfaces = [ "enp1s0" ];
    externalInterface = "wan0";
  };

  # ── DHCP: dnsmasq, DHCP-ONLY ─────────────────────────────────────────────
  # port=0 is non-negotiable: AdGuard owns :53 on this box
  # (modules/adguardhome.nix) and must not be fought with — same doctrine as
  # the coordinator's JBL segment (f9cb4236) and installer dnsmasq.
  # Option 6 hands every LAN client this box (= AdGuard) as resolver.
  services.dnsmasq = {
    enable = true;
    settings = {
      port = 0;
      interface = "enp1s0";
      bind-dynamic = true;
      dhcp-range = "10.42.0.10,10.42.0.200,255.255.255.0,12h";
      dhcp-option = [
        "option:router,10.42.0.1"
        "option:dns-server,10.42.0.1"
      ];
      dhcp-authoritative = true;
      # Infrastructure pins. The coordinator's is load-bearing: NAS-side
      # firewall rules and NFS export ACLs name 10.42.0.2 as a static fact.
      # MACs verified live 2026-08-20 (wlp192s0) / recorded in git pre-
      # retirement (BE550, ip neigh 2026-07).
      dhcp-host = [
        # The coordinator self-assigns .2 statically since the 2026-08-21
        # hardening (uplink-nas.nix); this pin remains as the guard that
        # keeps the pool from ever offering .2 to another MAC.
        "ac:f2:3c:35:1e:d1,coordinator,10.42.0.2,infinite"
        "98:03:8e:6b:61:e2,be550,10.42.0.3,infinite"
        # Brother HL-L2445DW — MAC from its mDNS hostname (BRW08F97E55F396),
        # confirmed via ARP from the coordinator on the Freebox segment
        # (2026-08-21, 192.168.1.38). The pin is LOAD-BEARING for printing
        # since the same-day hardening: in Deep Sleep the printer's mDNS
        # responder goes mute, so CUPS dials ipp://10.42.0.4 directly
        # (modules/printing.nix) and this address must never move.
        "08:f9:7e:55:f3:96,printer,10.42.0.4,infinite"
        # Worker — permanent fleet member (2026-08-21 ruling). Pinned ahead
        # of its full reintegration (#229) so its identity is stable for
        # firewall/SSH admissions from day one.
        "44:f7:9f:da:bd:1d,worker,10.42.0.5,infinite"
      ];
    };
  };

  # ── LAN admissions ───────────────────────────────────────────────────────
  # iifname, not saddr, for DHCP: DISCOVER arrives from 0.0.0.0 and a
  # source-IP match would drop it before dnsmasq ever saw it — the exact
  # failure the JBL segment hit (f9cb4236). DNS is iifname-scoped too: every
  # LAN client is a legitimate resolver client, not just the coordinator.
  networking.firewall.extraInputRules = ''
    iifname "enp1s0" udp dport 67 accept comment "DHCP for the BE550 LAN"
    iifname "enp1s0" udp dport 53 accept comment "AdGuard DNS for the BE550 LAN"
    iifname "enp1s0" tcp dport 53 accept comment "AdGuard DNS (TCP) for the BE550 LAN"
  '';

  # ── DNS hijack + encrypted-DNS bypass drops ──────────────────────────────
  # Ported verbatim in spirit from the retired plane. Prerouting DNAT catches
  # clients that ignore DHCP option 6 (Chromecasts, IoT); the forward drops
  # close the #46 escape hatch — Android "Automatic" Private DNS over
  # DoT/853 or DoH/443-to-known-DNS-IPs sails past a plaintext-only hijack,
  # verified live in AdGuard's querylog on the original segment. Dropping
  # them forces fallback to plaintext 53, which the DNAT then owns. Strict
  # (hostname-pinned) Private DNS remains a phone-side setting, as before.
  networking.nftables.tables.dns_hijack = {
    family = "inet";
    content = ''
      chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        ip daddr 10.42.0.1 return
        ip saddr 10.42.0.0/24 udp dport 53 dnat ip to 10.42.0.1
        ip saddr 10.42.0.0/24 tcp dport 53 dnat ip to 10.42.0.1
      }

      chain forward {
        type filter hook forward priority filter; policy accept;
        ip saddr 10.42.0.0/24 tcp dport 853 drop
        ip saddr 10.42.0.0/24 ip daddr {
          8.8.8.8, 8.8.4.4,
          1.1.1.1, 1.0.0.1,
          9.9.9.9, 149.112.112.112,
          208.67.222.222, 208.67.220.220
        } tcp dport 443 drop
      }
    '';
  };
}
