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
#
# WHAT THIS FILE DOES NOT SET IS ALSO LIVE CONFIG — read this before
# "completing" the settings block. AdGuard fills its config struct with its own
# defaults (internal/home/config.go) and unmarshals our YAML OVER it, so an
# omitted key is that default, not a zero value. Several of those defaults are
# load-bearing here: cache_enabled=true, enable_dnssec=true, refuse_any=true,
# handle_ddr=true, use_private_ptr_resolvers=true, filters_update_interval=24h,
# blocked_response_ttl=10s, querylog 90d / statistics 1d. That is why some keys
# below look like they "just set the default": on the box that owns :53 for the
# whole house, a default that can drift under a package bump is not a default
# worth relying on. Pinning is deliberate, not noise.
# ┌───────────────────────────────────────────────────────────────────────────┐
# │ 2026-09-03 — ADGUARD IS OFF IN CONFIG. See `adguardDown` in the let block │
# │ immediately below; that one boolean is the whole switch, and flipping it  │
# │ back to `false` restores every line of the arrangement described above.   │
# └───────────────────────────────────────────────────────────────────────────┘
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

  # ── #288/#289/#290: AdGuard disabled in config (2026-09-03) ───────────────
  # The bind list below pinned the NAS's tailnet address. The NAS re-registered
  # during the headscale migration and that address moved (100.89.54.51 →
  # 100.64.0.1), so AdGuard could not bind and exited 1 on every start. Because
  # resolved's global DNS on this box was 127.0.0.1 — i.e. AdGuard itself — a
  # dead AdGuard meant the NAS resolved nothing, and because the NAS is the
  # LAN's resolver (dnsmasq option 6 + the dns_hijack DNAT in
  # hosts/nas/router.nix), the whole house resolved nothing with it.
  #
  # It was stopped and `systemctl disable`d by hand, and the LAN has been held
  # up since by a RUNTIME-ONLY drop-in, /run/systemd/resolved.conf.d/
  # 99-adguard-down.conf, which evaporates on reboot and is reverted by any
  # rebuild. That made `nixos-rebuild` on this box a LAN-wide outage. This flag
  # makes the mitigation durable so a rebuild is safe again.
  #
  # TO REVERT, once the tailnet bind address is genuinely fixed:
  #   1. decide the tailnet bind: set `myAdguard.tailnetAddr` (hosts/nas) to the
  #      address `tailscale status` actually prints on the NAS, or leave it null
  #      to bind only loopback + 10.42.0.1 (the option cannot crash on a guess);
  #   2. set `adguardDown = false` here — nothing else in this file changes;
  #   3. re-invert the two paired assertions in flake.nix that name
  #      `nas.services.adguardhome.enable` and the resolved stub addresses.
  # Nothing about AdGuard's settings has been deleted: `services.adguardhome`
  # below is intact and still evaluated, so step 2 is genuinely a one-word flip.
  #
  # WHAT IS LOST WHILE THIS IS TRUE: DNS-level ad/tracker blocking for the whole
  # LAN, the query log, and DoH-encrypted upstreams (resolved forwards in
  # plaintext to the three public resolvers below — deliberately identical to
  # the runtime mitigation the operator has been running, rather than a
  # DNSOverTLS variant nobody has exercised on this box). Everything that must
  # keep WORKING — name resolution on the NAS, the LAN's resolver at
  # 10.42.0.1:53, the tailnet split-DNS listener, and the `.internal` names —
  # is carried over explicitly further down.
  adguardDown = true;

  # The fleet-internal service names, in ONE place. They are consumed twice:
  # by AdGuard's `rewrites` (when it runs) and by the /etc/hosts pin that
  # replaces those rewrites while `adguardDown` is true. Deriving both from
  # this list is what stops the two answers from drifting apart.
  # #136: paperless.internal resolves fleet-wide now, but answers only once
  # the myNas.paperless / myNasClient.relayPaperless pair flips on.
  internalNames = [
    "photos.internal"
    "music.internal"
    "videos.internal"
    "paperless.internal"
  ];

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
      # #288: off in config, not deleted. Everything below stays evaluated (the
      # upstream module wraps its whole `config` — assertions included — in
      # `mkIf cfg.enable`, so a disabled service with a full `settings` block is
      # inert, not an error) precisely so the flip back is one word.
      enable = !adguardDown;
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
          bind_hosts = [
            "127.0.0.1"
          ]
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

          # LAST RESORT, not a second opinion: fallback_dns is consulted only
          # when EVERY upstream_dns entry has failed outright — it is not the
          # per-query racing that upstream_mode does. It is deliberately
          # PLAINTEXT :53, because the failure it covers is "the encrypted
          # transport is unavailable at all" (a DPI'd or port-443-filtered
          # uplink — e.g. the day the house comes up on the coordinator's
          # freebox emergency rail instead of its own WAN), and a fallback that
          # speaks the same protocol as the thing that just died is not a
          # fallback. Quad9's pair, so the last-resort path is not the same
          # operator (Cloudflare) that is first on the hot path.
          fallback_dns = [
            "9.9.9.9"
            "149.112.112.112"
          ];

          # Cache. cache_enabled/cache_size are AdGuard's own defaults pinned
          # explicitly: this process is the whole house's resolver now, so a
          # package bump quietly changing either is a latency regression
          # nobody would think to blame on a rebuild.
          #
          # cache_optimistic is the real change: when an entry's TTL has
          # expired, answer from the stale entry IMMEDIATELY and refresh in
          # the background instead of making the client wait for a DoH round
          # trip. On a LAN that asks for the same few hundred names all day,
          # nearly every "miss" is a TTL expiry on a name we already know, and
          # the ISP-invisible upstream we chose is also the slowest part of
          # the path. Not set: cache_ttl_min/max — clamping TTLs means lying
          # to every client in the house about how long an answer is good for,
          # and no misbehaving upstream has been observed to warrant it.
          cache_enabled = true;
          cache_size = 4194304; # bytes; AdGuard's default, pinned
          cache_optimistic = true;

          # DNSSEC validation is a PIN of what this box already does, not a
          # new risk being taken: enable_dnssec defaults to TRUE in 0.107.78
          # (internal/home/config.go fills the config struct BEFORE our YAML
          # is unmarshalled over it, so every key this file omits is a live
          # default, not a zero value). Validation has therefore been on since
          # the 2026-07-13 rollout — the "stage it and watch for SERVFAIL
          # spikes" caution describes a decision that was already made by
          # omission a year ago. Written down so a future default flip cannot
          # silently turn it off.
          enable_dnssec = true;

          # EDNS Client Subnet stays OFF (also the default; pinned because it
          # is exactly what a "make DNS faster" pass reaches for). It exists
          # so CDN-geo-routing upstreams can see a client's subnet — useless
          # against plain recursive resolvers like these, and actively wrong
          # once mesh clients arrive: what would be forwarded to 1.1.1.1 is a
          # 100.64.0.0/10 CGNAT address, which tells the upstream nothing
          # except "this query came from a VPN-shaped range".
          edns_client_subnet.enabled = false;
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
          # Built from `internalNames` in the let block (2026-09-03) rather than
          # spelled out four times, so that this list and the /etc/hosts pin that
          # stands in for it while AdGuard is down cannot answer for different
          # sets of names.
          rewrites = map (domain: {
            enabled = true;
            inherit domain;
            answer = coordinatorAddr;
          }) internalNames;
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

    # Where resolved forwards. resolved itself is enabled fleet-wide in
    # common.nix; this only sets its upstream (and, while AdGuard is down, its
    # listeners). `Domains = "~."` is common to both branches and is the reason
    # the branch matters at all: it makes the GLOBAL route authoritative for every
    # name, so no per-link DNS pushed by the Freebox over wan0 can slip past.
    # Tailscale's own domains are more specific, so MagicDNS still wins either way.
    #
    # Only `Resolve` keys are set here, never the whole section: modules/common.nix
    # also writes `Resolve.MulticastDNS = false` into it and the two definitions
    # merge key-wise.
    services.resolved.settings.Resolve =
      if !adguardDown then
        {
          # Normal arrangement: AdGuard on loopback is the one upstream, so every
          # query on this box is filtered before it leaves.
          DNS = "127.0.0.1";
          Domains = "~.";
        }
      else
        # ── #288 mitigation, made durable ────────────────────────────────────
        # Field-for-field the runtime drop-in that is holding the LAN up right
        # now (/run/systemd/resolved.conf.d/99-adguard-down.conf, read live
        # 2026-09-03), so a rebuild REPLACES that file with an identical
        # permanent one instead of reverting it. Setting `enable = false` on its
        # own would have removed the resolver without replacing it — resolved's
        # DNS was 127.0.0.1, i.e. AdGuard — and produced the same LAN-wide
        # outage by a different route. This branch is what prevents that.
        {
          DNS = [
            "1.1.1.1"
            "8.8.8.8"
            "9.9.9.9"
          ];
          FallbackDNS = [
            "1.0.0.1"
            "8.8.4.4"
          ];
          Domains = "~.";
        }
        // lib.optionalAttrs isLanResolver {
          # THE LAN'S RESOLVER, taken over from AdGuard. resolved's stub normally
          # answers on 127.0.0.53 only; these extra listeners put it on the two
          # addresses clients actually dial, so nothing downstream has to change:
          #   10.42.0.1  — dnsmasq option 6 hands this to every LAN client and
          #                the dns_hijack DNAT (hosts/nas/router.nix) rewrites
          #                stragglers onto it. Admitted on enp1s0 there.
          #   100.64.0.1 — the tailnet node address the headscale console's
          #                split-DNS entry points at, so `.internal` keeps
          #                answering for roaming devices. Admitted on tailscale0
          #                at the bottom of this file.
          #
          # A pinned tailnet address here does NOT reintroduce #288. That bug was
          # a HARD bind failure: AdGuard exits 1 when an address in bind_hosts is
          # absent, and took the resolver down with it. systemd-resolved sets
          # IP_FREEBIND on its extra stub listeners, so a missing address is a
          # no-op — verified live on the coordinator 2026-09-03 by pointing
          # DNSStubListenerExtra at 10.42.0.199, an address that box does not
          # have: resolved started clean, stayed active, and 127.0.0.53 kept
          # answering. Worst case if this address moves again is that tailnet
          # split-DNS goes quiet; the LAN does not notice.
          DNSStubListenerExtra = [
            "10.42.0.1"
            "100.64.0.1"
          ];
        };

    # `.internal` while AdGuard is down (#288). AdGuard's `rewrites` above were
    # the ONLY answerer for these names on this LAN, so `enable = false` alone
    # loses them fleet-wide — measured live 2026-09-03 against 10.42.0.1, with
    # AdGuard already stopped: `coordinator` and `worker` answered from
    # /etc/hosts, `photos.internal` timed out.
    #
    # systemd-resolved synthesises answers from /etc/hosts for every query it
    # serves, the stub listeners included, so the same names come back from the
    # same address with no new daemon. Verified live on the coordinator the same
    # day by bind-mounting a probe /etc/hosts and querying the stub at
    # 127.0.0.53: multi-label `probe.internal` and `deep.sub.internal` both
    # answered, confirming this is not a single-label-only path. (`internal` is
    # also in resolved's built-in negative trust anchor list, so DNSSEC does not
    # object.)
    #
    # `coordinatorAddr` is 10.42.0.2 on this host — the same answer the rewrites
    # give — so this stays correct, and harmless, if AdGuard ever comes back:
    # /etc/hosts would simply answer first with an identical record. It can be
    # kept or dropped when `adguardDown` flips; it is not load-bearing then.
    # hosts/nas/network.nix defines the same key with [ "coordinator" ]; the two
    # list definitions merge.
    networking.hosts = lib.optionalAttrs (adguardDown && isLanResolver) {
      ${coordinatorAddr} = internalNames;
    };

    # LAN-resolver boot ordering (NAS only): the explicit 10.42.0.1 bind above
    # fails if AdGuard starts before NM has the static address up — the same
    # race that broke nfsd's hostName bind behind network-online.target (NM
    # reports online before the static address exists). Wait for the address
    # itself, not for a target that lies about it; 30s bound, then start anyway
    # and let Restart handle a genuinely late interface.
    #

    # LAN-resolver boot ordering (NAS only): the explicit 10.42.0.1 bind above
    # fails if AdGuard starts before NM has the static address up — the same
    # race that broke nfsd's hostName bind behind network-online.target (NM
    # reports online before the static address exists). Wait for the address
    # itself, not for a target that lies about it; 30s bound per address, then
    # start anyway and let Restart handle a genuinely late interface.
    # Gated on `!adguardDown` as well as `isLanResolver` (#288): a bare
    # `systemd.services.adguardhome` definition RENDERS A UNIT even when the
    # upstream module is disabled, and this one carries only ordering and an
    # ExecStartPre — no ExecStart — so leaving it live would write a broken
    # adguardhome.service into the system closure.
    systemd.services.adguardhome = lib.mkIf (isLanResolver && !adguardDown) (
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
    # admit :53 on the tailnet interface (NAS only). LAN admission lives in
    # hosts/nas/router.nix; this is its roaming twin. Deliberately NOT gated on
    # `adguardDown` — while AdGuard is off it is resolved's extra stub listener on
    # 100.64.0.1 answering here instead, and the door has to stay open for it.
    networking.firewall.interfaces.tailscale0 = lib.mkIf isLanResolver {
      allowedUDPPorts = [ 53 ];
      allowedTCPPorts = [ 53 ];
    };
  };
}
