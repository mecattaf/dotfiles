{ ... }:
{
  # One NIC, two rails (2026-08-20 router cutover, transitional). enp1s0 is
  # the live predictable name of the sole onboard NIC (Aquantia AQC113 10GbE
  # at PCI 01:00.0), recorded in the kexec installer 2026-08-01.
  #
  # address1 is this box's LAN identity: gateway + DNS for the BE550 segment
  # (hosts/nas/router.nix). address2 keeps the old /30 alive so the
  # coordinator's cable still works before AND during the physical move —
  # the move re-plugs the same port from the coordinator's NIC into the
  # BE550's switch, and because both addresses ride the one interface,
  # nothing about addressing changes when the wire does. The /30 (and its
  # transitional gateway below) dies in the post-cutover cleanup commit.
  #
  # gateway on the /30 with a deliberately BAD metric (700 > NM's wifi 600):
  # while the cable is plugged and wan0 is down, internet still arrives via
  # the coordinator's NAT exactly as today; the moment the A8500 associates,
  # its default route wins. Fail-safe in both directions during phase 1.
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
      address2 = "10.77.0.2/30";
      gateway = "10.77.0.1";
      route-metric = 700;
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

  # extraInputRules is an nftables-only option: under the default iptables
  # backend it renders NOTHING and the rules below silently vanish. That
  # sealed the first installed system shut (SSH dropped, ping-only; recovered
  # via the tty1 autologin getty on 2026-08-01). The nas-topology flake check
  # now asserts this stays on.
  networking.nftables.enable = true;

  # SSH admission — transitional dual-rail: the coordinator's old /30 address
  # and its pinned LAN lease are both welcome until the cleanup commit.
  # This one rule also carries borg (forced-command key, backups.nix) and the
  # coordinator's journal-archive ssh (journal-upload.nix). Everything else
  # SSH-shaped stays closed: headless.nix forces openssh.openFirewall=false.
  networking.firewall.extraInputRules = ''
    ip saddr { 10.77.0.1, 10.42.0.2 } tcp dport 22 accept comment "coordinator SSH (legacy /30 + LAN)"
  '';
}
