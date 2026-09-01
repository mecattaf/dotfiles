{
  config,
  lib,
  pkgs,
  ...
}:
# Per-machine AdGuard Home — the fleet's DNS ad/tracker filter, ONE loopback
# instance per box. This replaces the old coordinator-only LAN quadlet that
# filtered DNS for the now-retired BE550 wifi segment; the coordinator and the
# Ethernet-only NAS now filter their OWN queries (the zenbook-duo was the third
# importer until it left the fleet on 2026-08-30). Each host imports this module
# explicitly.
#
# Fully declarative: mutableSettings = false, so the entire config lives here in
# git and AdGuard NEVER runs its web setup wizard. AdGuardHome.yaml is
# regenerated from this on every rebuild; the UI at http://127.0.0.1:3000 is
# view-only (query log / stats), never the source of truth. Change a blocklist
# or rule HERE, not in the browser.
#
# Port-53 arrangement — the sensible, no-fighting approach: AdGuard binds
# LOOPBACK 127.0.0.1:53 ONLY (never 0.0.0.0), so it is not an open resolver and
# needs no firewall ports. systemd-resolved keeps its own stub on a DIFFERENT
# loopback IP (127.0.0.53:53) — no EADDRINUSE collision, so the old
# `DNSStubListener=no` hack is gone — and simply forwards everything to AdGuard
# as its upstream (DNS=127.0.0.1, Domains=~.). Resolution path:
#   app → nss-resolve → resolved (127.0.0.53) → AdGuard (127.0.0.1) → DoH upstream.
# Tailscale still injects *.ts.net as a more-specific per-link routing domain
# into resolved, so MagicDNS keeps winning for the tailnet — the reason we route
# through resolved instead of the naive `nameservers = [ "127.0.0.1" ]`, which
# would bypass resolved and break split-DNS across the mesh.
let
  # SPLIT-HORIZON `.internal` (2026-08-06). Every box used to get the same
  # hardcoded answer — the coordinator's TAILNET address, 100.105.121.73. That
  # made Tailscale load-bearing for traffic that never leaves the building:
  # the coordinator resolved its OWN service names to an address on tailscale0
  # and hairpinned out and back, and the NAS reached them only because the /30
  # cable happened to be blanket-trusted (the packet is for a local address, so
  # the kernel's weak host model accepts it off the wrong interface). Stop
  # tailscaled on the coordinator and photos.internal died on two hosts that
  # are physically wired together.
  #
  # The answer is now simply "the coordinator, as seen from THIS host", so the
  # tailnet is used only by the host that actually needs it:
  #   coordinator  loopback   — its own Caddy, never touches an interface
  #   nas          /30 cable  — hosts/coordinator/uplink-nas.nix
  # The fallback branch below is the roaming case. It had one real user, the
  # zenbook-duo (retired 2026-08-30), and is kept because it is what any future
  # off-LAN host would take — see #233, which wants it re-pointed anyway.
  coordinatorAddr =
    {
      coordinator = "127.0.0.1";
      # 2026-08-20 rewire: the coordinator's pinned lease on the BE550 LAN
      # (hosts/nas/router.nix dhcp-host), replacing its /30 address. On the
      # NAS this answer also serves every LAN client (phones included) now
      # that AdGuard fronts the whole segment: media keeps flowing through
      # the coordinator's Caddy + relays in phase 1, so .internal must keep
      # answering with the COORDINATOR until the phase-2 direct-serving
      # decision moves the front doors here.
      nas = "10.42.0.2";
    }
    .${config.networking.hostName} or "100.105.121.73";

  # The NAS is the only host whose AdGuard serves more than loopback: it is
  # the resolver for the whole BE550 LAN (2026-08-20 rewire).
  isLanResolver = config.networking.hostName == "nas";

  tailnetAddr = config.myAdguard.tailnetAddr;

  # Addresses AdGuard is told to bind EXPLICITLY, each paired with the device
  # it appears on, so the boot wait below can watch for the address itself
  # rather than a target that lies about it (see the block at the bottom).
  waitAddrs =
    lib.optionals isLanResolver [
      {
        dev = "enp1s0";
        addr = "10.42.0.1";
      }
    ]
    ++ lib.optionals (isLanResolver && tailnetAddr != null) [
      {
        dev = "tailscale0";
        addr = tailnetAddr;
      }
    ];
in
{
  # The NAS's tailnet-facing DNS bind, as an OPTION rather than the literal it
  # used to be. See the bind_hosts block for why this is not just tidying.
  options.myAdguard.tailnetAddr = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "100.64.0.1";
    description = ''
      Tailnet address of THIS host, bound by AdGuard in addition to loopback
      and the LAN address so mesh clients can query it directly at its node
      address (no subnet-route acceptance needed — what phones want).

      null means "bind nothing we cannot verify": mesh clients still resolve
      through 10.42.0.1 over the advertised 10.42.0.0/24 subnet route. Set it
      only to an address `tailscale status` has actually printed on this box —
      an address AdGuard cannot bind is a house-wide DNS outage, not a
      degradation.
    '';
  };

  config = {
    services.adguardhome = {
      enable = true;
      mutableSettings = false; # config is git, not the web wizard
      host = "127.0.0.1"; # web UI / query log — loopback only
      port = 3000;
      openFirewall = false; # loopback-only: nothing to expose

      settings = {
        # DNS resolver: loopback bind, DoH upstreams (encrypted end to end so the
        # ISP no longer sees plaintext lookups).
        #
        # The endpoints are IP-LITERAL DoH (1.1.1.1 / 9.9.9.9), not hostnames, on
        # purpose: a hostname endpoint (https://dns.cloudflare.com/…) makes AdGuard
        # first resolve that hostname over plain :53 via bootstrap_dns on every
        # cold start, so a network that filters outbound :53 (captive portals,
        # some hotel/guest LANs) would stall the resolver until bootstrap gives
        # up. An IP-literal endpoint connects straight to <ip>:443 with no :53
        # lookup at all — one less thing that can break on an unfamiliar network,
        # which matters for the roaming laptop. Verified live before fleet rollout
        # 2026-07-13: resolves + filters through this exact config. bootstrap_dns
        # is kept only to satisfy the mutableSettings=false assertion (must be a
        # non-empty list) and as a fallback if a hostname endpoint is ever added;
        # it is not on the hot path today.
        dns = {
          # LAN resolver (NAS only): bind the LAN address EXPLICITLY alongside
          # loopback, never 0.0.0.0 — resolved's stub holds 127.0.0.53:53, and
          # a wildcard :53 bind EADDRINUSEs against it (found as a crashloop on
          # first NixOS boot, recorded in the 26d4afdf retirement message). The
          # specific-address bind races address assignment at boot exactly like
          # nfsd did (hosts/nas/storage.nix lore); the ExecStartPre wait below
          # is the fix. Port 53 admission is scoped to the LAN interface in
          # hosts/nas/router.nix, not opened here.
          #
          # THE TAILNET ENTRY USED TO BE A LITERAL, 100.89.54.51, and it must
          # never come back as one. That address was minted by a control plane
          # this box no longer talks to: Tom's ruling 2026-09-01 moves the NAS's
          # own tailscaled onto the NAS's OWN headscale, which allocates out of
          # its own 100.64.0.0/10 pool, so the successor address is not knowable
          # at eval time and is not stable across a headscale DB rebuild either.
          #
          # A wrong literal here is not a degradation, it is a HOUSE-WIDE DNS
          # OUTAGE: AdGuard exits when it cannot bind a listed address, and this
          # process is the only thing answering :53 for every LAN client — the
          # dns_hijack chain in hosts/nas/router.nix DNATs them here even when
          # they ask someone else. So the address is now myAdguard.tailnetAddr,
          # default null, and mesh DNS does not wait on it being filled in:
          #   * a mesh client that takes the advertised 10.42.0.0/24 subnet route
          #     queries 10.42.0.1 and is answered today. The packet arrives on
          #     tailscale0 addressed to an address AdGuard already binds, and the
          #     kernel's weak host model delivers it off the "wrong" interface —
          #     the same property the .internal hairpin note above documents.
          #     The tailscale0 :53 door at the bottom of this file admits it.
          #   * querying the NAS at its own 100.64.x node address instead needs
          #     no route acceptance (phones and Windows take routes by default,
          #     Linux needs --accept-routes), and THAT is what the option is
          #     for: set it in hosts/nas/default.nix once `tailscale status` on
          #     the NAS has printed the headscale-issued address, rebuild, and
          #     the wait-for-address loop below picks it up with no other edit.
          bind_hosts =
            [ "127.0.0.1" ]
            ++ lib.optionals isLanResolver [ "10.42.0.1" ]
            ++ lib.optional (isLanResolver && tailnetAddr != null) tailnetAddr;
          port = 53;
          upstream_dns = [
            "https://1.1.1.1/dns-query"
            "https://1.0.0.1/dns-query"
            "https://9.9.9.9/dns-query"
          ];
          bootstrap_dns = [
            "1.1.1.1"
            "9.9.9.9"
          ];
          upstream_mode = "load_balance";
        };

        filtering = {
          protection_enabled = true;
          filtering_enabled = true;

          # Fleet-internal names under the ICANN-reserved private-use TLD
          # `.internal` (deliberately NOT mecattaf.dev — that zone is real and
          # public on Cloudflare; these names must scream intranet). Every box
          # running this filter resolves them to the coordinator over its
          # shortest path (`coordinatorAddr` above), where Caddy
          # (hosts/coordinator/nas-client.nix) routes them onto the NAS media
          # relays. Phones don't use these resolvers, so phone apps keep the
          # coordinator.tail8dd1.ts.net port URLs.
          rewrites = [
            {
              enabled = true;
              domain = "photos.internal";
              answer = coordinatorAddr;
            }
            {
              enabled = true;
              domain = "music.internal";
              answer = coordinatorAddr;
            }
            {
              enabled = true;
              domain = "videos.internal";
              answer = coordinatorAddr;
            }
            # #136: resolves fleet-wide now, but answers only once the
            # myNas.paperless / myNasClient.relayPaperless pair flips on.
            {
              enabled = true;
              domain = "paperless.internal";
              answer = coordinatorAddr;
            }
          ];
        };

        # Blocklists. AdGuard DNS filter is the network-level analog of the
        # AdGuard browser extension's base filter; Steven Black adds the classic
        # hosts-file coverage. IDs are arbitrary but must stay unique + stable.
        filters = [
          {
            enabled = true;
            id = 1;
            name = "AdGuard DNS filter";
            url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
          }
          {
            enabled = true;
            id = 2;
            name = "Steven Black hosts";
            url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
          }
        ];
      };
    };

    # Point resolved's upstream at AdGuard and make that route authoritative for
    # ALL names (~.), so no DHCP-pushed per-link DNS can slip past the filter.
    # resolved itself is enabled fleet-wide in common.nix; this only sets where it
    # forwards. Tailscale's ts.net domain is more specific, so MagicDNS still wins.
    services.resolved.settings.Resolve = {
      DNS = "127.0.0.1";
      Domains = "~.";
    };

    # LAN-resolver boot ordering (NAS only): the explicit 10.42.0.1 bind above
    # fails if AdGuard starts before NM has the static address up — the same
    # race that broke nfsd's hostName bind behind network-online.target (NM
    # reports online before the static address exists). Wait for the address
    # itself, not for a target that lies about it; 30s bound per address, then
    # start anyway and let Restart handle a genuinely late interface.
    systemd.services.adguardhome = lib.mkIf isLanResolver (
      {
        serviceConfig.ExecStartPre = pkgs.writeShellScript "wait-bind-addrs" ''
          ${lib.concatMapStringsSep "\n" (a: ''
            for _ in $(${pkgs.coreutils}/bin/seq 30); do
              ${pkgs.iproute2}/bin/ip -4 addr show dev "${a.dev}" 2>/dev/null \
                | ${pkgs.gnugrep}/bin/grep -q "${builtins.replaceStrings [ "." ] [ "\\." ] a.addr}/" && break
              ${pkgs.coreutils}/bin/sleep 1
            done
          '') waitAddrs}
          exit 0
        '';
        # RestartSec: upstream module already sets 10 — good enough for the
        # late-interface case; do not fight it.
      }
      # The tailscaled ordering exists ONLY for the tailnet bind, so it is gated
      # on there being one. With myAdguard.tailnetAddr unset the house resolver
      # no longer waits on the VPN control plane to come up at boot — a real win
      # now that the control plane is headscale running on this same box: a
      # headscale/tailscaled startup problem must not be able to delay :53 for
      # the whole LAN, and with no tailnet address to bind there is nothing on
      # tailscale0 for AdGuard to wait for.
      // lib.optionalAttrs (tailnetAddr != null) {
        after = [ "tailscaled.service" ];
        wants = [ "tailscaled.service" ];
      }
    );

    # Mesh devices query this resolver over the tailnet — either at the NAS's
    # node address (myAdguard.tailnetAddr, when set) or at 10.42.0.1 through the
    # advertised subnet route. Both arrive on tailscale0, so admission stays
    # interface-scoped and needs no edit when the control plane changes. LAN
    # admission lives in hosts/nas/router.nix; this is its roaming twin.
    networking.firewall.interfaces.tailscale0 = lib.mkIf isLanResolver {
      allowedUDPPorts = [ 53 ];
      allowedTCPPorts = [ 53 ];
    };
  };
}
