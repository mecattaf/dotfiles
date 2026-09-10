{
  config,
  lib,
  pkgs,
  ...
}:
# NAS-owned Headscale control plane; coordinator retains independent SaaS
# Tailscale as an emergency path. The current control URL is LAN-only.
# Preserve the NAS identity and restricted fleet policy across network moves.
# Public ingress is a separate task: see docs/nas/overseas-headscale.md.
let
  cfg = config.myNas.headscale;

  # Stable service address on the BE550 LAN. Firewall rules, not the bind
  # alone, determine which forwarded traffic can reach this listener.
  lanAddr = "10.42.0.1";

  # 8090, not 8080: atticd owns [::]:8080 on this box (hosts/nas/attic.nix),
  # which is a dual-stack wildcard and therefore also holds 127.0.0.1:8080.
  # Nothing else in the fleet claims 8090 (grepped 2026-09-01).
  port = 8090;

  # The URL clients are told to dial, and the URL headscale advertises as its
  # own. These MUST agree — a client whose ControlURL differs from the
  # server's server_url gets registration URLs pointing somewhere it cannot
  # reach. Phase 1 is the honest LAN answer; phase 2 is the public name.
  loginServer =
    if cfg.publicEndpoint.enable then
      "https://${cfg.publicEndpoint.hostname}:${toString cfg.publicEndpoint.port}"
    else
      "http://${lanAddr}:${toString port}";
in
{
  options.myNas.headscale = {
    enable = lib.mkEnableOption "the self-hosted headscale control plane on the NAS (Tom's ruling 2026-09-01, supersedes #233's tailscale.com design)";

    publicEndpoint = {
      enable = lib.mkEnableOption ''
        a public HTTPS Headscale endpoint. Disabled until a separate ingress
        design is validated; the wired migration makes no Freebox changes.
        See docs/nas/overseas-headscale.md for preserved overseas requirements.

        Enabling this changes server_url and re-enrolls the NAS automatically.
        Existing clients also need a planned control-URL migration. Provision
        and test ingress, DNS and the DNS-01 certificate secret first; the
        declarations below do not provide an internet route to this service.
      '';

      hostname = lib.mkOption {
        type = lib.types.str;
        default = "headscale.mecattaf.dev";
        description = ''
          Public FQDN for the control plane. On the real (public, Cloudflare)
          mecattaf.dev zone on purpose, unlike the intranet `.internal` names
          in modules/adguardhome.nix: a control server that friends' phones
          must reach needs a name that resolves and a cert that validates on
          the open internet, which is precisely what `.internal` refuses to
          be.

          Must NOT share a domain with `dns.base_domain` below — headscale
          requires those two to differ.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8443;
        description = ''
          Port for the dormant public HTTPS listener. The separate ingress
          follow-up must validate the endpoint and client migration before
          enabling it; changing this value changes the advertised control URL.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.headscale = {
      enable = true;

      # Explicit LAN bind (see `lanAddr` above). The module turns
      # address+port into settings.listen_addr via mkDefault.
      address = lanAddr;
      inherit port;

      settings = {
        server_url = loginServer;

        # ── DNS: headscale PUSHES resolvers, it never BINDS one ────────────
        # Nothing here opens a DNS listener, which is the whole reason this
        # service can coexist with AdGuard on the box that also runs the
        # LAN's only resolver. `dns.*` only sets what headscale hands clients
        # in their netmap; the client's own OS applies it. Port 53 on every
        # interface that matters stays owned by AdGuard + resolved and stays
        # defended by hosts/nas/router.nix's dns_hijack DNAT.
        dns = {
          magic_dns = true;

          # A STRICT SUBDOMAIN carved out for the tailnet, and deliberately
          # not bare `internal`: modules/adguardhome.nix already claims
          # photos/music/videos/paperless.internal via rewrites, and
          # base_domain is answered AUTHORITATIVELY by MagicDNS for its whole
          # subtree. Setting base_domain to `internal` would make headscale
          # and AdGuard two owners of one namespace — the exact ambiguity
          # hosts/nas/network.nix warns about for /etc/hosts. Under
          # hs.mecattaf.internal the two never overlap: AdGuard keeps
          # *.internal, headscale answers *.hs.mecattaf.internal.
          #
          # Also must differ from server_url's domain (module assertion, and
          # headscale's own requirement) — `.internal` vs `.dev` clears that
          # in both phases.
          base_domain = "hs.mecattaf.internal";

          # FALSE, deliberately. `true` would make 10.42.0.1 the resolver for
          # ALL DNS on every joined device, everywhere, always — ad-filtering
          # a friend's phone off-LAN is a nice side effect, but it also makes
          # this appliance a hard dependency for their entire internet and a
          # much bigger trust ask than "you can reach Tom's NAS". With it off,
          # a joined device keeps its own resolver for the open internet and
          # only sends the tailnet's own namespaces here.
          #
          # If Tom ever wants the global takeover for HIS OWN devices only,
          # the knob is per-device `nameservers.split`, not this boolean.
          override_local_dns = false;

          # AdGuard, at the LAN address it already binds
          # (modules/adguardhome.nix). Roaming clients reach it through the
          # subnet route this node advertises, and :53 on tailscale0 is
          # already admitted there — same rule, same reasoning, no change
          # needed on the AdGuard side for this to work.
          nameservers.global = [ lanAddr ];

          # THE SPLIT-DNS ENTRY, NOW IN GIT. modules/adguardhome.nix:104-110
          # describes this as "the admin console's split-DNS entry" — a
          # hand-made row in tailscale.com's web UI that sent tailnet
          # devices' `.internal` queries at the NAS. Self-hosting the control
          # plane means that row becomes a declared line here, reviewed and
          # rebuilt like anything else, instead of a click nobody can diff.
          #
          # WRITTEN TWICE, ON PURPOSE. Upstream headscale's own
          # config-example.yaml puts split DNS at `dns.nameservers.split`,
          # while the packaged NixOS module declares the option one level up as
          # `dns.split` — the rendered yaml therefore carries an empty
          # `dns.split: {}` from the module default no matter what we do. Both
          # keys take the same domain -> servers shape, viper ignores keys it
          # does not know, and getting this wrong fails SILENTLY (tailnet
          # clients simply never send `.internal` here). So set both and let
          # whichever one this headscale actually reads win.
          nameservers.split."internal" = [ lanAddr ];
          split."internal" = [ lanAddr ];
        };

        # Retain public DERP relays. They do not make the private control
        # endpoint reachable to new or reconnecting overseas clients.
        derp.server.enabled = false;

        # ── The management surfaces stay on loopback, forever ──────────────
        # gRPC is headscale's remote-admin API and upstream states plainly it
        # CANNOT be reverse-proxied; remote CLI use is out of scope, so this
        # never leaves 127.0.0.1 and never gets a firewall rule. Metrics the
        # same. Written explicitly rather than left to the packaged defaults
        # so a future reader can see they were considered and closed.
        grpc_listen_addr = "127.0.0.1:50443";
        grpc_allow_insecure = false;
        metrics_listen_addr = "127.0.0.1:9099";

        # TLS is Caddy's job, never headscale's — upstream recommends
        # terminating in the reverse proxy, so tls_cert_path/tls_key_path and
        # tls_letsencrypt_hostname are left at their packaged defaults (unset).
        # Phase 1 has no TLS at all (plain HTTP on a LAN this box routes);
        # phase 2 puts Caddy in front. Either way headscale serves cleartext
        # to a local peer and holds no certificate material of its own.

        # sqlite at /var/lib/headscale/db.sqlite with WAL on — the packaged
        # default, and right for a personal + friends tailnet. Consistent
        # backups are handled separately by headscale-backup.nix.
        database.type = "sqlite";

        # ── The ACL policy is a FILE IN THIS REPO, from day one ────────────
        # Deny-by-default since 2026-09-10: NAS admin SSH into tag:fleet;
        # fleet may fetch signed offers/cache from the NAS only. This is
        # reviewed in git and reloadable with `systemctl reload headscale`.
        policy = {
          mode = "file";
          path = ./headscale-policy.hujson;
        };
      };
    };

    # ── Boot ordering: wait for the address, not for a target that lies ────
    # Same race, same fix as modules/adguardhome.nix's ExecStartPre: the
    # explicit 10.42.0.1 bind fails if the service starts before
    # NetworkManager has the static address up, and network-online.target
    # reports online before that address exists. headscale's stock
    # Restart=always/RestartSec=5s would eventually win, but a unit that
    # crashloops through its first minute of every boot is noise on a box
    # whose failure surfacing (modules/failure-surfacing.nix) is supposed to
    # mean something. 30s bound, then start anyway and let Restart handle a
    # genuinely late interface.
    systemd.services.headscale.serviceConfig.ExecStartPre =
      pkgs.writeShellScript "wait-headscale-bind-addr" ''
        for _ in $(${pkgs.coreutils}/bin/seq 30); do
          ${pkgs.iproute2}/bin/ip -4 addr show dev enp1s0 2>/dev/null \
            | ${pkgs.gnugrep}/bin/grep -q '10\.42\.0\.1/' && break
          ${pkgs.coreutils}/bin/sleep 1
        done
        exit 0
      '';

    # ── Make the documented policy-reload command actually exist ───────────
    # headscale re-reads its policy file on SIGHUP, and the whole point of
    # keeping the ACL in git is that changing it is a reload rather than a
    # restart (a restart drops every node's long-poll and re-does the netmap
    # for no reason). The packaged unit declares no ExecReload, so
    # `systemctl reload headscale` — which this file, the policy file and
    # docs/nas/headscale-2026-09-01.md all tell the operator to run — would
    # otherwise fail with "unit cannot be reloaded". One line, and the
    # instruction becomes true.
    systemd.services.headscale.serviceConfig.ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";

    # ── The NAS as a CLIENT of its own control plane ───────────────────────
    #
    # LOOPBACK-ISH, NOT THE PUBLIC NAME, in phase 1: the box points at the
    # address it itself binds, so reaching its own control server involves no
    # DNS it does not own and no hairpin out through the Freebox and back.
    # This is the same split-horizon doctrine modules/adguardhome.nix applies
    # to photos.internal — the host that OWNS a service dials it locally,
    # everyone else dials the real name.
    #
    # In phase 2 loginServer becomes the public HTTPS name, and the
    # networking.hosts pin below keeps the split-horizon property: this box
    # resolves that name to its own LAN address and hits its own Caddy, never
    # the Freebox's public IP.
    #
    # --login-server goes ONLY in extraUpFlags. `tailscale set` has no such
    # flag, and the packaged module runs `tailscale set <extraSetFlags>`
    # unconditionally (systemd.services.tailscaled-set) — putting it there
    # would fail that unit on every boot.
    #
    # --reset makes the up idempotent across prefs that were written by the
    # tailscale.com era; without it `tailscale up` can refuse with "changing
    # settings via 'tailscale up' requires mentioning all settings".
    # This box enables its OWN tailscaled. Until 2026-09-01 the enable came
    # from modules/common.nix's fleet-wide default; that default is being
    # retired in the same series (tailscale.com survives only on the
    # coordinator, as the Freebox emergency rail), and a headscale client
    # whose daemon exists at another module's pleasure would go dark the
    # moment that module forgets it.
    services.tailscale.enable = true;
    services.tailscale.useRoutingFeatures = "server";
    services.tailscale.extraUpFlags = lib.mkForce [
      "--ssh"
      "--advertise-routes=10.42.0.0/24"
      "--login-server=${loginServer}"
      "--reset"
    ];
    services.tailscale.extraSetFlags = lib.mkForce [
      "--ssh"
      "--advertise-routes=10.42.0.0/24"
    ];
    # The runtime-minted key from headscale-nas-enroll below. Setting this is
    # what brings the packaged tailscaled-autoconnect unit into existence at
    # all — and extraUpFlags are ONLY applied by that unit, so without an
    # authKeyFile the --login-server above would be inert decoration. The old
    # arrangement's "login is interactive, no authkey secret lands on the
    # appliance" still holds in the sense that mattered: no secret lands on
    # this box AT REST. It is minted here, used once, and dies with /run.
    services.tailscale.authKeyFile = "/run/headscale-nas-enroll/authkey";

    # Phase 2 only: this box resolves its own control name to itself.
    networking.hosts = lib.mkIf cfg.publicEndpoint.enable {
      ${lanAddr} = [ cfg.publicEndpoint.hostname ];
    };

    # ── headscale-nas-enroll: mint locally, join locally, no secret at rest ─
    #
    # Runs between tailscaled and tailscaled-autoconnect and does three
    # things, all idempotent:
    #   1. ensures the headscale user `tom` exists (see the policy file for
    #      why one user per PERSON and not per device);
    #   2. mints a single-use, 1h, tag:mesh preauth key into /run and leaves
    #      it there for autoconnect's --auth-key;
    #   3. performs the CONTROL-PLANE CUTOVER: if tailscaled is currently
    #      registered against a different control URL (i.e. official
    #      tailscale.com, which is exactly the state of this box before this
    #      commit deploys), it logs out so autoconnect re-registers against
    #      headscale. A logged-in node is otherwise `Running`, and
    #      autoconnect never calls `tailscale up` on a Running node — so
    #      without this step the migration would silently never happen.
    #
    # DEPLOY THIS OVER THE LAN, NOT OVER THE TAILNET. Step 3 drops this box's
    # tailscale.com session on purpose; doing it from a session that rides
    # that very tunnel cuts the branch you are sitting on. Same register as
    # hosts/nas/nix-on-nvme.nix's "never flip this remotely".
    #
    # A key is minted on every start rather than only when one is needed:
    # single-use and 1h-expiring, so an unused one is a dead row in
    # /var/lib/headscale/db.sqlite and nothing else, and the alternative
    # (conditionally leaving the file absent) hands autoconnect a `cat` of a
    # missing path in exactly the race we are trying to remove.
    #
    # MANUAL FALLBACK, if the CLI shape below ever drifts under a headscale
    # bump (written against 0.29.3 per research, CORRECTED 2026-09-01: the stable
    # pin actually ships 0.28.0 — verified live, the grants-refusal proved it):
    #   headscale users create tom
    #   headscale users list                       # note the numeric id
    #   headscale preauthkeys create -u <id> -e 1h --tags tag:mesh
    #   tailscale up --login-server=<loginServer> --auth-key <key> \
    #     --ssh --advertise-routes=10.42.0.0/24 --reset
    systemd.services.headscale-nas-enroll = {
      description = "Mint a local headscale preauth key for this node and cut it over from any foreign control plane";
      after = [
        "headscale.service"
        "tailscaled.service"
      ];
      wants = [
        "headscale.service"
        "tailscaled.service"
      ];
      # The hard edge to autoconnect, expressed from this side so it lives in
      # one place: autoconnect REQUIRES the mint and is ordered after it. If
      # the mint fails, autoconnect does not run and never `cat`s a missing
      # file. tailscaled itself stays up either way, so a failed enroll costs
      # this box its tailnet identity, not the house router.
      requiredBy = [ "tailscaled-autoconnect.service" ];
      before = [ "tailscaled-autoconnect.service" ];
      path = [
        config.services.headscale.package
        config.services.tailscale.package
        pkgs.jq
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        # DELIBERATELY NOT RemainAfterExit. A oneshot that never stays active
        # is re-run every time something Requires= it, which makes
        # `systemctl restart tailscaled-autoconnect` mint a FRESH key rather
        # than re-feeding autoconnect the used, expired one — the single
        # recovery command for "this node lost its tailnet identity". The cost
        # of that choice is that the runtime directory would normally be reaped
        # the instant this unit exits, i.e. before autoconnect ever reads the
        # key; RuntimeDirectoryPreserve is what buys it back.
        RuntimeDirectory = "headscale-nas-enroll";
        RuntimeDirectoryMode = "0700";
        RuntimeDirectoryPreserve = "yes";
      };
      script = ''
        # NixOS wraps every `script =` in `bash -e`, and this script's whole
        # design contradicts -e: it degrades on purpose (the four-shape mint,
        # the || true logout) and exits FATAL only where it says FATAL.
        # Learned live 2026-09-01, deploy #2: headscale's unit reports ready
        # a beat before its API answers, the first CLI probe of an
        # unprotected assignment failed in that beat, and -e turned it into
        # an instant status=5 death with zero log output — which failed the
        # entire NAS activation. -e goes OFF before anything else runs.
        set +e
        set -uo pipefail
        keyfile="$RUNTIME_DIRECTORY/authkey"
        want='${loginServer}'

        # 1. headscale must be answering on its unix socket. The CLI reaches
        #    it via /etc/headscale/config.yaml (written by the packaged
        #    module) and /run/headscale/headscale.sock; root gets in
        #    regardless of the 0750/0770 headscale-group modes.
        ready=0
        for _ in $(seq 60); do
          if headscale users list >/dev/null 2>&1; then ready=1; break; fi
          sleep 1
        done
        if [ "$ready" -ne 1 ]; then
          echo "FATAL: headscale did not answer its socket within 60s" >&2
          exit 1
        fi

        # 2. The `tom` user, idempotently.
        getuid() {
          headscale users list -o json 2>/dev/null \
            | jq -r '.[] | select(.name == "tom") | .id' 2>/dev/null | head -n1
        }
        uid="$(getuid)"
        if [ -z "$uid" ] || [ "$uid" = "null" ]; then
          echo "creating headscale user 'tom'"
          headscale users create tom --display-name "Tom" || true
          uid="$(getuid)"
        fi
        if [ -z "$uid" ] || [ "$uid" = "null" ]; then
          echo "FATAL: no headscale user 'tom' and could not create one" >&2
          exit 1
        fi

        # 3. Mint. Four attempts, narrowing from "what we want" to "what
        #    certainly works", because this runs on the house router and a
        #    CLI-shape drift must degrade rather than wedge:
        #      json + tag:mesh -> json untagged -> text + tag:mesh -> text
        #    An untagged key is a working key; the tag is a scheme we are
        #    establishing early (see the policy file), and a headscale that
        #    refuses a tag it has no tagOwners entry for must not cost this
        #    box its tailnet identity.
        plausible() {
          # A headscale preauth key is a long opaque token, one line, no
          # spaces. Anything shorter than this is a log line, not a key.
          [ "$(printf '%s' "$1" | wc -c)" -ge 24 ]
        }
        mint_json() {
          headscale preauthkeys create -u "$uid" -e 1h "$@" -o json 2>/dev/null \
            | jq -r '.key // empty' 2>/dev/null | head -n1
        }
        mint_text() {
          headscale preauthkeys create -u "$uid" -e 1h "$@" 2>/dev/null \
            | tail -n1 | tr -d '[:space:]'
        }
        key=""
        for attempt in json-tagged json-plain text-tagged text-plain; do
          case "$attempt" in
            json-tagged) candidate="$(mint_json --tags tag:mesh)" ;;
            json-plain)  candidate="$(mint_json)" ;;
            text-tagged) candidate="$(mint_text --tags tag:mesh)" ;;
            text-plain)  candidate="$(mint_text)" ;;
          esac
          if [ -n "$candidate" ] && plausible "$candidate"; then
            key="$candidate"
            echo "minted a preauth key ($attempt)"
            break
          fi
        done
        if [ -z "$key" ]; then
          echo "FATAL: could not mint a headscale preauth key" >&2
          exit 1
        fi
        umask 0077
        printf '%s\n' "$key" > "$keyfile"
        chmod 0400 "$keyfile"

        # 4. THE CUTOVER. `tailscale debug prefs` carries the ControlURL the
        #    daemon is actually registered against — the one thing
        #    `tailscale status` will not tell us and the only way to
        #    distinguish "logged into headscale" from "logged into
        #    tailscale.com" without guessing.
        cur=""
        for _ in $(seq 30); do
          cur="$(tailscale debug prefs 2>/dev/null | jq -r '.ControlURL // empty' 2>/dev/null)"
          if [ -n "$cur" ]; then break; fi
          sleep 1
        done
        if [ -n "$cur" ] && [ "$cur" != "$want" ]; then
          echo "control plane moving: $cur -> $want; logging out of the stale one"
          # Bounded: logging out of a control server that is unreachable (the
          # Freebox is down, tailscale.com is unreachable) must not hang the
          # boot of the house router.
          timeout 30 tailscale logout || true
        fi
        exit 0
      '';
    };

    # ── Firewall: the NAS's extraInputRules idiom, interface-scoped ────────
    # hosts/nas/network.nix:68-73 records why this box uses raw nftables
    # snippets rather than networking.firewall.interfaces.<if>.allowedTCPPorts
    # like the rest of the fleet, and flake.nix's nas-topology check pins the
    # nftables backend so they render. Keep control-plane admissions separate
    # from the DNS listener's interface port list.
    networking.firewall.extraInputRules = ''
      iifname "enp1s0" tcp dport ${toString port} accept comment "headscale control plane, BE550 LAN"
      iifname "tailscale0" tcp dport ${toString port} accept comment "headscale re-auth over an already-established tunnel"
    ''
    + lib.optionalString cfg.publicEndpoint.enable ''
      iifname "enp1s0" tcp dport ${toString cfg.publicEndpoint.port} accept comment "headscale HTTPS (Caddy), BE550 LAN"
      iifname "tailscale0" tcp dport ${toString cfg.publicEndpoint.port} accept comment "headscale HTTPS (Caddy) re-auth over an established tunnel"
    '';

    # Dormant HTTPS origin and DNS-01 certificate configuration. Public ingress
    # remains undesigned; this block alone does not make the service reachable.
    # Caddy forwards Headscale's control-protocol upgrades to the local server.
    security.acme = lib.mkIf cfg.publicEndpoint.enable {
      acceptTerms = true;
      defaults.email = "thomas@mecattaf.dev";
      certs.${cfg.publicEndpoint.hostname} = {
        dnsProvider = "cloudflare";
        # Provision this secret only as part of the reviewed public-ingress
        # follow-up; it is not needed while the endpoint remains disabled.
        environmentFile = "/run/agenix/cloudflare-dns-acme";
        # lego must ask a PUBLIC resolver whether the TXT record has
        # propagated: this box's own resolver chain (AdGuard) answers from
        # cache and would race the challenge.
        dnsResolver = "1.1.1.1:53";
        group = "caddy";
        reloadServices = [ "caddy" ];
      };
    };
    services.caddy = lib.mkIf cfg.publicEndpoint.enable {
      enable = true;
      # The site address carries the port and the scheme: one listener on
      # cfg.publicEndpoint.port, TLS from the lego-minted cert above (that is
      # what useACMEHost wires), no :80 listener, no HTTP->HTTPS redirect
      # because there is nothing to redirect from.
      virtualHosts."https://${cfg.publicEndpoint.hostname}:${toString cfg.publicEndpoint.port}" = {
        useACMEHost = cfg.publicEndpoint.hostname;
        extraConfig = ''
          reverse_proxy ${lanAddr}:${toString port}
        '';
      };
    };

    # Overseas devices make re-enrollment costly. headscale-backup.nix now
    # snapshots the live SQLite database consistently and preserves the Noise
    # identity on the separate data disk. See docs/nas/headscale-backup.md for
    # verification, the manual pre-handover backup, and restore limitations.
  };
}
