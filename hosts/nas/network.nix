{ ... }:
{
  # One NIC, one rail. enp1s0 is the live predictable name of the sole
  # onboard NIC (Aquantia AQC113 10GbE at PCI 01:00.0), recorded in the
  # kexec installer 2026-08-01.
  #
  # The sole address is this box's LAN identity: gateway + DNS for the BE550
  # segment (hosts/nas/router.nix). The transitional /30 second rail
  # (10.77.0.2 + gateway-via-coordinator, the pre-move tether) was RETIRED
  # 2026-08-21 evening: the physical cable is gone, wan0 owns the default
  # route, and — the bug that forced the timing — Avahi was announcing
  # 10.77.0.2 as this box's mDNS address, so every `nas.local` click from
  # Nautilus dialed a dead rail. One address, no ambiguity.
  # The profile KEEPS its historical id on purpose: ensureProfiles only
  # creates/updates profiles it names — it never deletes others. A renamed id
  # would leave the old coordinator-fast-lane profile alive beside this one,
  # both autoconnect on enp1s0, and NM could keep picking the stale one
  # (whose /30 gateway carries a better metric). Same id = in-place update,
  # no fight. The name is now a misnomer for a LAN+legacy dual profile;
  # rename only in the post-cutover cleanup commit, deleting the old profile
  # imperatively (`nmcli con delete coordinator-fast-lane`) in the same pass.
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
      # Own DNS plane (AdGuard via resolved, modules/adguardhome.nix); never
      # accept resolvers from anyone else.
      ignore-auto-dns = true;
    };
    ipv6.method = "ignore";
  };

  # The coordinator as seen from this host: its pinned LAN lease
  # (hosts/nas/router.nix dhcp-host), with the /30 name kept as a comment of
  # record until the cleanup commit retires that rail.
  networking.hosts."10.42.0.2" = [ "coordinator" ];

  # The worker as seen from this host: its STATIC lease-free LAN identity
  # (declared in hosts/worker/default.nix, guarded by the dnsmasq dhcp-host pin
  # in hosts/nas/router.nix — not a DHCP outcome). This host's Immich dials
  # http://worker:3003 for every ML batch (./media.nix, #229) and the appliance
  # has no mDNS and no bare-hostname resolution, so without this pin that URL is
  # a black hole.
  #
  # HOST-SCOPED HERE ON PURPOSE, moved out of modules/common.nix 2026-08-31
  # (#277). 10.42.0.5 is the house 6 GHz wifi — right for this consumer, wrong
  # for the twins, which reach each other on the 5GbE/Thunderbolt rails
  # (coordinator -> 10.42.0.5 measured 104.895 ms avg on 2026-08-31 against
  # 0.109 ms to the 10.99.9.2 fleet identity). The twins answer `worker` from
  # modules/fleet-hosts.nix (#273) instead. The two consumers genuinely want
  # different answers, and each host gets exactly ONE: nsswitch runs `resolve`
  # ahead of `files`, so two entries for one name are ordered by
  # systemd-resolved and not by /etc/hosts — first-match is not a knob we own.
  #
  # The NAS is deliberately NOT on the fleet rails: it is a wired appliance on
  # the LAN it also routes, so this wifi address is the only path it has to the
  # worker. If Immich ML ever needs the wire, the fix is a rail to this box, not
  # a second entry here.
  networking.hosts."10.42.0.5" = [ "worker" ];

  # extraInputRules is an nftables-only option: under the default iptables
  # backend it renders NOTHING and the rules below silently vanish. That
  # sealed the first installed system shut (SSH dropped, ping-only; recovered
  # via the tty1 autologin getty on 2026-08-01). The nas-topology flake check
  # now asserts this stays on.
  networking.nftables.enable = true;

  # SSH admission — the coordinator's static LAN address only (/30 rail
  # swept 2026-08-21 along with every other 10.77.0.1 admission fleet-wide).
  # This one rule also carries the coordinator's journal-archive ssh
  # (journal-upload.nix). Everything else
  # SSH-shaped stays closed: headless.nix forces openssh.openFirewall=false.
  networking.firewall.extraInputRules = ''
    ip saddr 10.42.0.2 tcp dport 22 accept comment "coordinator SSH (LAN; /30 retired 2026-08-21)"
  '';
}
