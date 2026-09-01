{
  config,
  lib,
  pkgs,
  ...
}:
# ─── The fleet's OWN control plane: headscale on the NAS (2026-09-01) ───────
#
# Tom's ruling 2026-09-01: "self-hosted headscale server lands on the NAS and
# becomes the control plane for everything — his devices, future friend
# devices. The NAS's own tailscaled will point at its local headscale."
#
# This SUPERSEDES the design in #233, which had the NAS and the coordinator
# both on official tailscale.com (NAS primary sink, coordinator emergency
# rail). The split survives; the control plane under the NAS half does not.
# After today:
#
#   nas          headscale server  +  tailscale CLIENT of its own headscale
#   coordinator  official tailscale.com, always-connected-but-idle — the
#                EMERGENCY RAIL, do not remove, do not clean up (see
#                hosts/coordinator/*, modules/common.nix; not this file's lane)
#   worker       no tailnet at all, of either kind (unchanged)
#
# MUST NEVER COME BACK, stated the way AGENTS.md states these things: official
# tailscale.com is no longer a control plane for the NAS. If this box is ever
# found registered against controlplane.tailscale.com, that is a regression to
# be undone, not a fallback that healed itself — the escape hatch is the
# coordinator's node plus the Freebox, deliberately on the OTHER box, because a
# single-point-of-failure escape hatch that lives on the failing box is not an
# escape hatch. Equally: the coordinator's tailscale + freebox-uplink pair must
# never be "tidied away" because headscale exists now.
#
# ── WHY THE SUBNET ROUTER SURVIVES THE CONTROL-PLANE SWAP ──────────────────
# hosts/nas/default.nix's old block advertised 10.42.0.0/24 so "a roaming
# laptop reaches every home device through one node". That premise is about
# ROAMING CLIENTS, not about whose control plane issues the netmap: headscale
# speaks the same protocol and the same subnet-router feature. So
# useRoutingFeatures = "server" and --advertise-routes stay exactly as they
# were, and the flake's nas-topology / fleet-connectivity asserts on those
# three knobs stay green by design rather than by edit. What changes is one
# flag (--login-server) and one fact (which server holds the node keys).
#
# ── PHASING, and what is honestly NOT true yet ─────────────────────────────
# PHASE 1 (this commit, gate ON): headscale answers on the LAN address only,
# plain HTTP, port 8090. Every NixOS box on 10.42.0.0/24 can join, the NAS
# joins itself, MagicDNS + split-DNS-to-AdGuard are configured and live. What
# this does NOT do is make headscale reachable from outside the house: there is
# no port-forward on the Freebox and no public DNS name. So until phase 2,
# headscale is a HOME-ONLY control plane and the coordinator's tailscale.com
# node remains the only actual remote-access path. Stated plainly so nobody
# reads "the control plane for everything" off the ruling and assumes the
# roaming half already works.
#
# PHASE 2 (myNas.headscale.publicEndpoint.enable, gate OFF — runbook in its
# own option description below): Caddy terminates TLS for a real public name
# and wan0 admits :80/:443. That gate is the FIRST deliberate breach of this
# box's "wan0 admits nothing unsolicited" invariant (asserted as settled
# doctrine at hosts/nas/tv.nix:117 and hosts/nas/attic.nix:84) — which is
# exactly why it is a gate with a runbook and not three lines in this commit.
#
# ── NO NEW SECRET, BY CONSTRUCTION ─────────────────────────────────────────
# The appliance is a recipient of exactly ONE ciphertext (huggingface-token,
# secrets.nix `nasOnly`) and that invariant is untouched here. headscale's
# noise_private.key is SELF-GENERATED into /var/lib/headscale on first start —
# server-identity state, not a credential anyone mints. The NAS's own preauth
# key is MINTED AT RUNTIME by headscale-nas-enroll below, from the headscale
# that is running on this very box, into /run — so it never exists at rest,
# never enters git, and needs no agenix door at all. There is deliberately no
# secrets/tailscale-authkey-nas.age and there must not be one.
#
# ── DOCS ───────────────────────────────────────────────────────────────────
# docs/nas/headscale-2026-09-01.md carries the user/tag scheme, the
# key-minting workflow for the future public omarchy-nix-fleet repo, the
# phase-2 exposure runbook, and the ops/backup gap.
let
  cfg = config.myNas.headscale;

  # The LAN address this box already owns as gateway/DHCP/DNS
  # (hosts/nas/network.nix). Bind EXPLICITLY to it, never 0.0.0.0 — the same
  # doctrine modules/adguardhome.nix records for :53, and here it has a second
  # payoff: a listener bound to 10.42.0.1 cannot be reached from wan0 at all,
  # so the WAN invariant is enforced by the bind and not only by nftables.
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
        the PUBLIC headscale endpoint: Caddy + TLS on this box and an
        unsolicited-traffic door on wan0.

        GATE OFF until the runbook below has been walked, because three of its
        five steps happen outside this repo and the fourth is a documented
        reversal of stated policy.

        RUNBOOK (phase 2):
          1. Freebox OS (http://mafreebox.freebox.fr, LAN-side admin):
             a. pin a static DHCP lease for the NAS's wan0 permanent MAC
                (hosts/nas/a8500.nix) so the forward target cannot drift;
             b. forward exactly ONE TCP port — `port` below, default 8443 —
                to that address. NOT :80, NOT :443 (Tom's ruling 2026-09-01:
                the public door is nonstandard and isolated, which also
                sidesteps Free's shared-IPv4 trap — a line on "IPv4
                partagee" owns only a slice of the address's ports, never
                :443; if the panel shows a partagee range, either request
                full-stack IPv4 there or pick the forwarded port from the
                allotted range and set `port` to match). No UDP 3478 — the
                embedded DERP server stays off, see the derp block below.
                For the record, nothing else contends for Freebox forwards:
                the coordinator's tailscale.com fallback is outbound-only
                NAT traversal and needs no inbound port at all.
          2. Freebox DynDNS (same admin panel, dyndns.freebox.fr) or a
             Cloudflare-API updater, because the Freebox holds a residential
             and probably dynamic public IP.
          3. Cloudflare DNS for the name in `hostname`: an A record that is
             GREY-CLOUD / DNS-ONLY. Orange-cloud proxying BREAKS headscale —
             the control channel is a POST with `Upgrade:
             tailscale-control-protocol`, and Cloudflare's proxy does not
             support that WebSocket-over-POST mechanism. This is upstream's
             own documented limitation (and it rules out Cloudflare Tunnel
             for the same reason), not a preference.
          4. The cert secret (DNS-01 — with no :80 or :443 forwarded,
             HTTP-01 and TLS-ALPN-01 are both impossible, ACME validates via
             DNS instead): mint a Cloudflare API token scoped to Zone.DNS
             edit on the mecattaf.dev zone ONLY, then
               nix develop -c agenix -e secrets/cloudflare-dns-acme.age
             containing the single line
               CF_DNS_API_TOKEN=<token>
             and wire it per the house pattern: a nasOnly-tier entry in
             secrets.nix plus, in this file's phase-2 block, an
             age.secrets.cloudflare-dns-acme line feeding the
             security.acme environmentFile below. The declarations are NOT
             pre-written because agenix eval needs the .age file to exist;
             the acme block below names the runtime path it expects.
          5. Flip this gate and deploy. Note that the server_url CHANGES with
             it (LAN URL -> public URL WITH the port), so every
             already-registered node has to be re-pointed once: on the NAS
             the enroll unit below does it automatically (it logs out of the
             stale control URL and re-registers); anywhere else it is one
             `tailscale up --login-server=https://<hostname>:<port> --force-reauth`.
             Doing phase 2 BEFORE any friend device joins costs one node's
             churn; doing it after costs everyone's.
          6. Verify from off-LAN (phone on LTE): the custom-server login flow
             in the Tailscale app must reach name:port and get a valid cert.

        WHAT THIS GATE ADMITS, stated once so it is never a surprise: an
        UNSOLICITED inbound door on wan0. Every other line in hosts/nas/*
        says the Freebox side admits nothing (tv.nix:117, attic.nix:84).
        That doctrine is being deliberately narrowed, not deleted: exactly
        ONE nonstandard TCP port, terminated by Caddy, reverse-proxied to a
        LAN-bound headscale, and nothing else on wan0 changes.
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
          The ONE public TCP port (Tom's ruling 2026-09-01: nonstandard, so
          the WAN door stays isolated from everything else that could ever
          want :443 — and usable even on a shared-IPv4 Free line, where :443
          is not Tom's to forward; on such a line set this to a port inside
          the allotted range). Baked into server_url, so changing it after
          nodes have registered costs the same re-point churn as changing the
          hostname. Caddy listens on it directly; there is no :80 and no
          redirect — a door that answers exactly one protocol on exactly one
          port.
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

        # ── DERP: embedded relay OFF, public relay map KEPT ────────────────
        # Relay and control are independent planes: a node authenticating
        # against this headscale is perfectly happy relaying through
        # Tailscale Inc.'s public DERP fleet when it cannot get a direct
        # WireGuard path. Upstream's own doc says the embedded server has "no
        # speed or throughput optimisations" and becomes a single point of
        # failure once the public map is dropped.
        #
        # Rejected deliberately: enabling it here would put a second
        # self-hosted single point of failure behind the same box that is
        # already the house router, and would need UDP 3478 forwarded on the
        # Freebox for STUN — a third hole in the wan0 invariant, bought for a
        # relay we have no measured need for. Revisit only if two friend
        # devices are observed failing to connect through the public map.
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
        # default, and right for a personal + friends tailnet. Postgres would
        # be a second stateful service on an appliance for no gain. See the
        # BACKUP GAP note further down: this state is on the root filesystem
        # and NOTHING in this repo snapshots it today.
        database.type = "sqlite";

        # ── The ACL policy is a FILE IN THIS REPO, from day one ────────────
        # Even though today's content is allow-all. The point is that the
        # MECHANISM exists before the first friend key is ever minted: policy
        # in git, reviewed in a diff, rebuilt onto the box, reloadable with
        # `systemctl reload headscale`. The user/tag scheme and the
        # deny-all-baseline shape it grows into are written out in the file's
        # own header so the future omarchy-nix-fleet repo has an unambiguous
        # target to mint keys against.
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
    # nftables backend so they render at all. Note this also keeps the
    # fleet-connectivity check's EXACT-SET assert on
    # interfaces.tailscale0.allowedTCPPorts ([ 53 5900 ]) meaningful and
    # untouched: the tailnet door is widening for a deliberate reason, and it
    # is doing so where this host says such doors go.
    networking.firewall.extraInputRules = ''
      iifname "enp1s0" tcp dport ${toString port} accept comment "headscale control plane, BE550 LAN"
      iifname "tailscale0" tcp dport ${toString port} accept comment "headscale re-auth over an already-established tunnel"
    ''
    + lib.optionalString cfg.publicEndpoint.enable ''
      iifname "enp1s0" tcp dport ${toString cfg.publicEndpoint.port} accept comment "headscale HTTPS (Caddy), BE550 LAN"
      iifname "tailscale0" tcp dport ${toString cfg.publicEndpoint.port} accept comment "headscale HTTPS (Caddy) re-auth over an established tunnel"
      iifname "wan0" tcp dport ${toString cfg.publicEndpoint.port} accept comment "PHASE-2 WAN DOOR, the only one: headscale control plane from the internet (see myNas.headscale.publicEndpoint)"
    '';

    # ── Phase 2: Caddy in front on the ONE nonstandard port, DNS-01 certs ──
    # This block originally shipped as HTTP-01 on :80/:443 precisely to avoid
    # a Cloudflare API token at rest on this appliance. Tom's ruling
    # 2026-09-01 ("nonstandard port, clean and isolated") reversed that
    # trade knowingly: with no :80 and no :443 forwarded, HTTP-01 and
    # TLS-ALPN-01 are both physically impossible (ACME dials only those two
    # ports), so DNS-01 is not a preference here, it is the only remaining
    # challenge. The token is an agenix ciphertext scoped to Zone.DNS edit on
    # one zone (runbook step 4) — no plugin and no vendor hash even so,
    # because the ACME client is lego via security.acme, not a caddy build.
    #
    # Caddy and not nginx for a load-bearing protocol reason, not taste:
    # headscale's control channel is a POST carrying `Upgrade:
    # tailscale-control-protocol`, which nginx and Apache need explicit
    # header-passthrough stanzas to survive. Caddy's reverse_proxy handles
    # protocol upgrades natively.
    security.acme = lib.mkIf cfg.publicEndpoint.enable {
      acceptTerms = true;
      defaults.email = "thomas@mecattaf.dev";
      certs.${cfg.publicEndpoint.hostname} = {
        dnsProvider = "cloudflare";
        # Minted in runbook step 4; the age.secrets line that materializes
        # this path is added in the same flip commit (it cannot be
        # pre-written — agenix eval requires the .age file to exist).
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

    # ── THE BACKUP GAP, stated rather than skipped ─────────────────────────
    # /var/lib/headscale is on the ROOT filesystem, and hosts/nas/snapshots.nix
    # covers exactly six Btrfs subvolumes under /mnt/nas — none of which is
    # this. So the control plane's database (node keys, users, preauth keys,
    # ACL state) is NOT backed up by anything in this repo today. Recorded as a
    # known, accepted gap rather than silently left: the blast radius of losing
    # it is "every node re-registers", which is cheap and bounded, and it is
    # emphatically not the irreplaceable-media class of data the snapshot
    # schedule exists for. If it ever stops being cheap (friend devices Tom
    # cannot walk over to), the fix is a timer running
    # `sqlite3 db.sqlite '.backup …'` — never a naive file copy, because WAL
    # mode is on and db.sqlite alone is an inconsistent snapshot.
    #
    # noise_private.key lives in the same directory and is server-identity
    # state, self-generated on first start. It is not a secret to mint and not
    # a thing to put in agenix; losing it costs a re-handshake, not data.
  };
}
