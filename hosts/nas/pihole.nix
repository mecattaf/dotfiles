{
  config,
  lib,
  modulesPath,
  ...
}:
# Pi-hole v6 on the house router in SHADOW MODE — Tom's ruling 2026-09-01:
# "Pi-hole gets added on the NAS in SHADOW MODE: evaluation only — own DNS port
# and web UI, actively resolving/filtering for testing, but NOT advertised to
# any client (DHCP/DNS advertisement unchanged)."
#
# So this box now runs TWO filtering resolvers at once and exactly one of them
# is wired to anything:
#
#   AdGuard Home  :53 on 127.0.0.1 + 10.42.0.1 (+ the tailnet address)
#                 = THE resolver. dnsmasq's option:dns-server hands 10.42.0.1
#                   to every LAN client (hosts/nas/router.nix), the dns_hijack
#                   DNAT drags the stragglers back to it, and resolved forwards
#                   the NAS's own lookups to it. Untouched by this file.
#   Pi-hole FTL   :5335, wildcard bind, listeningMode LOCAL, admitted through
#                 the firewall from the COORDINATOR ONLY
#                 = the challenger, reachable only by someone who deliberately
#                   types `-p 5335`. Web UI on :5336, LOOPBACK ONLY.
#
# Nothing in the DHCP/DNS advertisement path is edited by this file, and the
# assertions at the bottom make that structural rather than a promise: they
# fail the build if Pi-hole ever lands on :53, if it ever turns its DHCP or NTP
# server on, if AdGuard stops owning :53, or if dnsmasq stops advertising
# 10.42.0.1. A shadow resolver that can be promoted by accident is not a shadow
# resolver.
#
# WHY at all: AdGuard has been the only filter this house has ever measured, so
# "is it the right one" has never been answered with data. Pi-hole is the only
# serious alternative with a native NixOS module at this pin, and the honest way
# to compare two filters is to run both against the same upstreams and diff
# their verdicts — not to read two feature matrices. docs/nas/pihole-shadow-
# 2026-09-01.md is the comparison runbook and carries the promotion/retirement
# decision criteria.
#
# ── The upstream module's dnsmasq assertion is a FALSE POSITIVE here ─────────
# `services.pihole-ftl` at this pin (nixpkgs-stable, pihole-ftl 6.7) carries a
# blanket refusal:
#
#   assertion = !config.services.dnsmasq.enable;
#   message   = "pihole-ftl conflicts with dnsmasq. Please disable one of them.";
#
# That guard exists because FTL *embeds* dnsmasq, so two of them on one box
# normally means a fight over :53, :67 and the lease file. On THIS box the fight
# cannot happen and every leg of it is already asserted somewhere:
#
#   :53  dnsmasq is DNS-DISABLED (`port = 0`, hosts/nas/router.nix:143, asserted
#        in flake.nix's nas-topology) and FTL is on :5335 (asserted below).
#   :67  dnsmasq owns DHCP; FTL's `dhcp.active` stays false (asserted below).
#   :123 FTL's NTP server — a v6 addition the old wisdom about Pi-hole does not
#        mention at all — is forced OFF below, all three legs of it.
#   leases  FTL never writes one, because its DHCP never starts.
#
# Disabling one of the two, as the message suggests, is not on the table: dnsmasq
# is this house's DHCP server and Pi-hole is the thing being evaluated.
#
# Rejected alternatives, in the order they were considered:
#   - `assertions = lib.mkForce [...]` — mkForce on that option discards EVERY
#     assertion in the fleet's evaluation, including the ~255 in flake.nix's own
#     checks. Not a scalpel, a wrecking ball.
#   - vendoring a patched copy of the 450-line upstream module into modules/ —
#     silently rots on the next `nix flake update nixpkgs-stable`, and rot in a
#     copied systemd unit is invisible.
#   - a bespoke systemd unit around pkgs.pihole-ftl — throws away upstream's
#     hardening block, tmpfiles, user, logrotate and the declarative `lists`
#     loader, i.e. re-implements the module to avoid one boolean.
#   - a nixos-container so the inner eval has no dnsmasq — a whole extra network
#     namespace and a second system closure to dodge one assertion.
# What is done instead: disable the upstream module by path and re-import the
# SAME file with that one assertion filtered out by its exact message. If
# upstream restructures the module or reworks the message, this stops matching
# and eval fails LOUDLY (either a missing attribute or the assertion coming back
# and firing) — which is the correct failure mode for a deliberate override.
#
# `modulesPath`, not `pkgs.path`: `imports` must not depend on `config`, and
# `pkgs` is derived from config — reading it here is an infinite-recursion trap.
# modulesPath is a specialArg, so it is safe and it is self-consistent (it names
# the very nixpkgs this host's closure evaluates from, inputs.nixpkgs-stable per
# flake.nix:474, without this file having to know that).
let
  cfg = config.myNas.piholeShadow;

  # Ports. Chosen against the whole box, not just against AdGuard:
  #   53          AdGuard DNS (LAN + tailnet)          modules/adguardhome.nix
  #   67          dnsmasq DHCP                         hosts/nas/router.nix
  #   3000        AdGuard web UI (loopback)            modules/adguardhome.nix
  #   5353        Avahi mDNS                           hosts/nas/discovery.nix
  #   5900        wayvnc (TV corner)                   hosts/nas/tv.nix
  #   8080        attic, bound 0.0.0.0 LAN-wide        hosts/nas/attic.nix
  #   19532       journald-remote                      hosts/nas/journal.nix
  #   28981/2284  Paperless / Immich                   hosts/nas/{paperless,media}.nix
  #   2049/445/22 NFS / SMB / SSH
  #
  # 5335 for DNS is the self-hosted-DNS community's conventional "second
  # resolver" port (the slot Unbound usually takes behind a Pi-hole), which makes
  # `dig -p 5335` read as "ask the other one" to anyone who has seen the pattern.
  #
  # 5336 for the web UI rather than the obvious 8081, deliberately: the 8xxx
  # block on this box is the crowded one and it is about to get worse. attic
  # already owns 8080 LAN-wide, and headscale — landing on this same box under
  # today's other ruling — defaults to 8080 for its control plane and therefore
  # has to be moved somewhere, with 8081 the first place anybody moves it to.
  # Parking the shadow UI next to the shadow resolver keeps the pair legible and
  # keeps it out of that argument entirely. Neither port appears anywhere else in
  # the tree (grepped 2026-09-01).
  dnsPort = 5335;
  webPort = 5336;

  # The incumbent, named rather than restated, so the assertions below compare
  # against what AdGuard actually is at eval time instead of a literal that can
  # drift out from under them.
  adguard = config.services.adguardhome;

  # See the header. Matched on the exact upstream message string.
  dnsmasqConflictMessage = "pihole-ftl conflicts with dnsmasq. Please disable one of them.";
  # The formals are spelled out rather than taken as a bare `args:` — the module
  # system builds a module function's argument set from its DECLARED formals
  # (lib.functionArgs), so a pattern-less lambda is handed only config/options
  # and the re-imported module dies on a missing `pkgs`. Found the honest way,
  # by eval failure, on first build.
  piholeFtlWithoutDnsmasqRefusal =
    {
      config,
      lib,
      pkgs,
      ...
    }@args:
    let
      upstream = import "${modulesPath}/services/networking/pihole-ftl.nix" args;
    in
    upstream
    // {
      config = upstream.config // {
        content = upstream.config.content // {
          assertions = lib.filter (a: a.message != dnsmasqConflictMessage) upstream.config.content.assertions;
        };
      };
    };
in
{
  disabledModules = [ "services/networking/pihole-ftl.nix" ];
  imports = [ piholeFtlWithoutDnsmasqRefusal ];

  options.myNas.piholeShadow.enable = lib.mkEnableOption ''
    Pi-hole v6 on the NAS in SHADOW MODE: a second filtering resolver on :5335
    with a loopback web UI, actively resolving and filtering for evaluation but
    advertised to nobody. AdGuard Home stays the resolver every client uses.
    Flipping this OFF is the whole retirement procedure
  '';

  config = lib.mkIf cfg.enable {
    # ── Shadow-mode tripwires ────────────────────────────────────────────────
    # These live here rather than in flake.nix's nas-topology check on purpose:
    # they are invariants OF this arrangement, so they should travel with the
    # file that creates it and die with it when the gate flips off. Promotion
    # means editing them, which is exactly the deliberate act that promotion
    # should be.
    assertions = [
      {
        assertion = config.services.pihole-ftl.settings.dns.port != 53;
        message = ''
          myNas.piholeShadow: the shadow resolver must never bind :53. That port
          is AdGuard's (modules/adguardhome.nix) and it is the port every LAN
          client, the dns_hijack DNAT and resolved all dial. Two filters on it
          is not a comparison, it is an outage.
        '';
      }
      {
        assertion = config.services.pihole-ftl.settings.dns.port != adguard.settings.dns.port;
        message = "myNas.piholeShadow: DNS port collides with AdGuard's own dns.port.";
      }
      {
        assertion = adguard.enable && adguard.settings.dns.port == 53;
        message = ''
          myNas.piholeShadow is SHADOW mode: it presumes AdGuard Home is still
          the resolver on :53. If AdGuard is being moved off :53, this is a
          PROMOTION and not a shadow deployment — rewrite this file (see the
          promotion section of docs/nas/pihole-shadow-2026-09-01.md) instead of
          letting the two swap silently.
        '';
      }
      {
        assertion = !config.services.pihole-ftl.settings.dhcp.active;
        message = ''
          myNas.piholeShadow: FTL's DHCP server must stay off. dnsmasq is this
          house's DHCP server (hosts/nas/router.nix) and a second one on the
          segment hands out leases pointing at the shadow resolver — the exact
          "not advertised to any client" line this mode is built around.
        '';
      }
      {
        assertion =
          !config.services.pihole-ftl.settings.ntp.ipv4.active
          && !config.services.pihole-ftl.settings.ntp.ipv6.active
          && !config.services.pihole-ftl.settings.ntp.sync.active;
        message = ''
          myNas.piholeShadow: FTL's NTP server AND its clock-sync client must
          stay off. Pi-hole v6 ships both ON by default (pihole.toml
          [ntp.ipv4]/[ntp.ipv6]/[ntp.sync]), which on this box would mean the
          evaluation instance serving time to the LAN on :123 and setting the
          HOUSE ROUTER's clock behind systemd-timesyncd's back.
        '';
      }
      {
        assertion =
          !config.services.pihole-ftl.openFirewallDNS
          && !config.services.pihole-ftl.openFirewallDHCP
          && !config.services.pihole-ftl.openFirewallWebserver;
        message = ''
          myNas.piholeShadow: the module's openFirewall* switches open their
          ports globally with no source restriction. Admission on this box is
          hand-written nftables scoped to one source address (see below and
          hosts/nas/network.nix:68-73 for why this box uses that idiom).
        '';
      }
      {
        assertion = builtins.any (lib.hasInfix "option:dns-server,10.42.0.1") (
          lib.toList config.services.dnsmasq.settings.dhcp-option
        );
        message = ''
          myNas.piholeShadow: DHCP must still advertise 10.42.0.1 (= AdGuard) as
          the LAN resolver. This assert is the load-bearing half of "NOT
          advertised to any client": it fires if anyone ever points option 6 at
          the shadow instance, whatever address or port they use to do it.
        '';
      }
    ];

    services.pihole-ftl = {
      enable = true;

      # Full statistics (0). The whole point of this instance is per-query
      # detail to diff against AdGuard's query log; an anonymising privacy level
      # would leave nothing to compare.
      privacyLevel = 0;

      # All three stay false — see the assertion above. Admission is the
      # extraInputRules block at the bottom of this file.
      openFirewallDNS = false;
      openFirewallDHCP = false;
      openFirewallWebserver = false;

      # Mirror AdGuard's two blocklists exactly (modules/adguardhome.nix
      # `filters`), because a filter comparison in which the two sides read
      # different lists measures the lists, not the filters.
      #
      # KNOWN ASYMMETRY, and it is itself a finding to write up: filter_1.txt is
      # AdGuard/ABP SYNTAX, not a hosts file. Pi-hole's gravity ingests the
      # plain `||domain^` subset of ABP and skips everything with modifiers or
      # regex, so Pi-hole's effective list is a SUBSET of AdGuard's from the
      # same URL. Measure the gravity domain count against AdGuard's rule count
      # before drawing any conclusion from a blocked-percentage difference.
      # Steven Black is a pure hosts file and imports whole on both sides.
      lists = [
        {
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
          type = "block";
          enabled = true;
          description = "AdGuard DNS filter (ABP syntax; gravity takes the ||domain^ subset)";
        }
        {
          url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
          type = "block";
          enabled = true;
          description = "Steven Black hosts (mirrors modules/adguardhome.nix filter id 2)";
        }
      ];

      settings = {
        dns = {
          port = dnsPort;

          # LOCAL: answer only clients whose address is on a subnet this box has
          # an interface for. FTL still binds the WILDCARD (the toml's own
          # [dns] listeningMode text spells this out) and origin-filters in
          # process — which is what we want here, because the alternative,
          # BIND + interface = "enp1s0", would race NetworkManager's static
          # address at boot exactly like AdGuard's explicit 10.42.0.1 bind does
          # (that race is why adguardhome.nix carries a 30s ExecStartPre
          # wait-for-the-address loop). A wildcard bind on an unused port needs
          # no wait loop, and :5335 is admitted from exactly one source address,
          # so the wildcard costs nothing. ALL was never a candidate: that is
          # how a house router becomes an open resolver.
          listeningMode = "LOCAL";

          # Same three resolvers AdGuard forwards to, so the two see identical
          # upstream answers and any verdict difference is the FILTER.
          #
          # TRANSPORT ASYMMETRY, deliberate and documented: FTL 6.7 has no
          # native DoH/DoT — this pin's pihole.toml describes `upstreams` as
          # "IP addresses and/or hostnames, optionally with a port (#...)" and
          # nothing else — so the shadow instance talks plaintext Do53 while
          # AdGuard talks DoH to the same endpoints. That is acceptable for a
          # FILTERING comparison (blocklist coverage, false positives, blocked
          # share) and it is NOT acceptable as a promotion: see the promotion
          # section in the doc. Pointing FTL at AdGuard (127.0.0.1#53) to
          # borrow its DoH was rejected outright — AdGuard would filter first
          # and Pi-hole would never see anything left to block, destroying the
          # only measurement this instance exists to take.
          upstreams = [
            "1.1.1.1"
            "1.0.0.1"
            "9.9.9.9"
          ];

          # NULL (0.0.0.0) is Pi-hole's own default and the closest analogue to
          # AdGuard's default blocked response; stated explicitly so a future
          # upstream default change cannot quietly move the goalposts mid-eval.
          blocking.mode = "NULL";

          # The plaintext dnsmasq-style query log at
          # /var/log/pihole/pihole.log is OFF: upstream's logrotate rule covers
          # FTL.log ONLY, so this log grows unbounded on an appliance whose
          # eMMC/NVMe siting has already cost one incident
          # (docs/nas/emmc-relief-2026-08-22.md). Nothing is lost for the
          # evaluation — the web UI's query log and every statistic read
          # pihole-FTL.db, which privacyLevel 0 fills regardless.
          queryLogging = false;
        };

        # ── The two v6 servers nobody expects Pi-hole to have ────────────────
        # DHCP: dnsmasq's job on this box, forever. `active` already defaults
        # false; stated anyway because "the default is false" is not a promise
        # anyone can read off this file, and the assertion above cites it.
        dhcp.active = false;

        # NTP: on by DEFAULT in Pi-hole v6, both the server and the clock-sync
        # client. On the house router that is a stray :123 listener on every
        # interface plus a second thing writing the system clock. Off, all three
        # legs, and asserted.
        ntp = {
          ipv4.active = false;
          ipv6.active = false;
          sync.active = false;
        };

        # Query storage bounded to two weeks. Upstream's own default is 91 days
        # and the module ships a separate weekly `queryLogDeleter` timer for the
        # same job — redundant here, so it stays off: FTL's maxDBdays already
        # prunes, and an evaluation instance has no business holding a quarter
        # of the household's DNS history on the router's disk. Two weeks is more
        # than the comparison window the doc asks for.
        database.maxDBdays = 14;

        webserver = {
          # Deny-all-except-loopback, evaluated inside FTL independently of
          # nftables. The UI is already loopback-bound below, so this is the
          # second lock on the same door — cheap, and it is the layer that
          # survives someone "temporarily" widening the bind.
          acl = "+127.0.0.1,+[::1]";
        };

        misc = {
          # FTL renices ITSELF to -10 by default. The evaluation instance must
          # never outrank the resolver the whole house actually depends on, and
          # AdGuard asks for no priority at all.
          nice = 0;

          # Belt and braces on top of the platform: pihole.toml is a Nix store
          # symlink whatever this says (upstream sets environment.etc, mode 400,
          # so the UI/API/CLI could not persist a change even if allowed), and
          # readOnly stops the API from pretending otherwise. Same doctrine as
          # AdGuard's mutableSettings = false: the config is git, the UI is a
          # window. Upstream mkDefault's this to true; pinned explicitly so the
          # doctrine is stated in the file that owns it.
          readOnly = true;
        };
      };
    };

    # The dashboard, via the thin upstream wrapper — it exists to write
    # webserver.{domain,port,paths} into the settings above, and taking the
    # webroot from the matching pihole-web package rather than hand-pointing at
    # a store path is the whole value it adds.
    #
    # LOOPBACK ONLY, mirroring AdGuard's own 127.0.0.1:3000 posture exactly
    # (modules/adguardhome.nix:71-73): the access model is an SSH tunnel,
    #   ssh -L 5336:127.0.0.1:5336 nas   ->   http://127.0.0.1:5336
    # not a LAN door. The v6-only ports syntax accepts an address prefix, so the
    # bind is spelled here and not in a firewall rule; `o` on the v6 loopback
    # keeps a missing ::1 from being fatal to the DNS engine.
    #
    # NO PASSWORD, and that is the considered answer, not an oversight: Pi-hole
    # v6 treats an empty webserver.api.pwhash as "no authentication", which is
    # precisely the posture AdGuard already runs here (it has no declarative
    # `users:` block either) — access control is the bind + the ACL + nftables,
    # all three of which are tighter for Pi-hole than for AdGuard. Setting a
    # hash inline was rejected on secret-safety grounds: `settings` renders
    # through pkgs.formats.toml into a WORLD-READABLE store path, so the /etc
    # file's mode 400 would be theatre. If a real login gate is ever wanted, the
    # door is FTL's FTLCONF_webserver_api_pwhash env override delivered via
    # systemd EnvironmentFile from a nasOnly agenix secret (root-read by PID 1
    # before the User=pihole drop) — one more ciphertext through the door
    # hosts/nas/default.nix:54-70 describes, never a wholesale re-admission.
    # That is written up in the doc's manual steps and is NOT built today.
    services.pihole-web = {
      enable = true;
      # Cosmetic identity in the UI chrome. Deliberately resolves NOWHERE: the
      # `.internal` rewrites live in modules/adguardhome.nix, and adding
      # pihole-shadow.internal there would be the first step of promotion, not
      # of evaluation.
      hostName = "pihole-shadow.internal";
      ports = [
        "127.0.0.1:${toString webPort}"
        "[::1]:${toString webPort}o"
      ];
    };

    # ── Admission: one source, one port ──────────────────────────────────────
    # extraInputRules, not interfaces.<if>.allowedTCPPorts — this box's
    # deliberate deviation from the fleet idiom, recorded at
    # hosts/nas/network.nix:68-73 and hosts/nas/router.nix:26-28, and pinned by
    # nas-topology's `assert nas.networking.nftables.enable` (under the iptables
    # backend these rules render as NOTHING and the appliance seals itself shut
    # — hit live 2026-08-01).
    #
    # Source-scoped to the coordinator, matching the SSH admission in
    # hosts/nas/network.nix:80-82, rather than iifname-scoped to the LAN the way
    # AdGuard's :53 is. AdGuard is iifname-scoped because every LAN client is a
    # legitimate client of it; the shadow resolver has exactly one legitimate
    # client, the box where the comparison is driven from. A phone must not be
    # able to reach this even by accident.
    #
    # The dns_hijack DNAT does not touch :5335 traffic (it matches dport 53
    # only, and returns early for `ip daddr 10.42.0.1` regardless), so
    # `dig -p 5335 @10.42.0.1 example.com` from the coordinator lands on FTL
    # unmangled. FTL's own upstream queries are locally generated, so they never
    # traverse the prerouting or forward chains that drop the LAN's encrypted-
    # DNS bypass attempts.
    #
    # No :5336 rule: the web UI is loopback-bound, so there is nothing to admit.
    networking.firewall.extraInputRules = ''
      ip saddr 10.42.0.2 udp dport ${toString dnsPort} accept comment "pihole SHADOW DNS from coordinator (evaluation only, hosts/nas/pihole.nix)"
      ip saddr 10.42.0.2 tcp dport ${toString dnsPort} accept comment "pihole SHADOW DNS (TCP) from coordinator (evaluation only)"
    '';
  };
}
