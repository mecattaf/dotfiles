# headscale on the NAS — the fleet's own control plane (2026-09-01)

Tom's ruling, 2026-09-01: *"self-hosted headscale server lands on the NAS and
becomes the control plane for everything — my devices, future friend devices.
The NAS's own tailscaled will point at its local headscale."*

This page is the operator-facing half of `hosts/nas/headscale.nix` and
`hosts/nas/headscale-policy.hujson`. It records what landed, what did not, the
runbooks that only Tom can walk, and the two cross-cutting hazards this change
creates elsewhere in the repo.

## What this supersedes

Issue **#233** (*"NAS sink becomes the primary tailnet path; coordinator tailnet
+ freebox-uplink formalized as emergency rails"*) designed the NAS/coordinator
split with **both** boxes on official tailscale.com. The split survives
verbatim; the control plane under the NAS half does not.

| Host | before 2026-09-01 | after |
|---|---|---|
| **nas** | tailscale.com node, subnet router, interactive login | **headscale server** + tailscale client of its own headscale, same subnet router |
| **coordinator** | tailscale.com node, `--ssh` | unchanged — **EMERGENCY RAIL**, always-connected-but-idle, do not remove, do not clean up |
| **worker** | no tailnet | unchanged |

The subnet-router role is deliberately unchanged: `useRoutingFeatures =
"server"` and `--advertise-routes=10.42.0.0/24` were never about *whose* control
plane issued the netmap, they were about roaming clients reaching the house.
headscale speaks the same protocol and the same feature. That is also why the
`nas-topology` and `fleet-connectivity` flake asserts on those three knobs stay
green without an edit.

**Must never come back** (stated in the AGENTS.md register, where a
decommissioned thing gets an explicit prohibition rather than a silent
omission): official tailscale.com is no longer a control plane for the NAS. A
NAS found registered against `controlplane.tailscale.com` is a regression to
undo, not a fallback that healed itself. And the coordinator's tailscale +
`freebox-uplink` pair must never be tidied away on the grounds that headscale
exists now — an escape hatch that lives on the box which might be the thing
failing is not an escape hatch.

## Shape as deployed (phase 1)

```
                 ┌──────────────────────── nas ────────────────────────┐
  BE550 LAN      │                                                     │
  10.42.0.0/24 ──┤ 10.42.0.1:8090  headscale  ── /var/lib/headscale     │
                 │                 (sqlite, noise key, self-generated) │
                 │ 10.42.0.1:53    AdGuard Home (unchanged owner of DNS)│
                 │ tailscale0      tailscaled, client of ^ headscale    │
  wan0 ──────────┤ (admits nothing unsolicited — unchanged in phase 1)  │
                 └─────────────────────────────────────────────────────┘
```

- **Port 8090**, not 8080: atticd owns `[::]:8080` on this box, and that
  dual-stack wildcard also holds `127.0.0.1:8080`.
- **Bound explicitly to `10.42.0.1`**, never `0.0.0.0` — the same doctrine
  `modules/adguardhome.nix` records for `:53`, with a second payoff here: a
  listener bound to the LAN address cannot be reached from `wan0` at all, so the
  WAN invariant is enforced by the bind and not only by nftables.
- **Firewall doors** (`networking.firewall.extraInputRules`, the NAS's idiom):
  `enp1s0 tcp/8090` for LAN clients, `tailscale0 tcp/8090` so an
  already-connected node whose key expired can re-auth over the tunnel it still
  has. Nothing on `wan0`. `interfaces.tailscale0.allowedTCPPorts` is untouched,
  so `fleet-connectivity`'s exact-set assert (`[ 53 5900 ]`) stays meaningful.
- **gRPC (`50443`) and metrics (`9099`) stay on loopback forever.** Upstream
  states plainly that gRPC cannot be reverse-proxied; remote CLI use is out of
  scope.
- **Embedded DERP is OFF**, and the public Tailscale DERP map is kept. Relay and
  control are independent planes: a node authenticating here relays through
  Tailscale Inc.'s DERP fleet quite happily. Enabling the embedded server would
  add a second self-hosted single point of failure behind the box that is
  already the house router, and would need UDP 3478 forwarded — a third hole in
  the WAN invariant bought for a relay with no measured need. Revisit only if
  two friend devices are *observed* failing to connect.

### DNS: headscale pushes, AdGuard resolves

headscale's `dns.*` settings open no listener. They only set what headscale
hands clients in their netmap, which each client's own OS applies. Port 53 stays
owned by AdGuard + `systemd-resolved` and stays defended by `router.nix`'s
`dns_hijack` DNAT.

| setting | value | why |
|---|---|---|
| `magic_dns` | `true` | |
| `base_domain` | `hs.mecattaf.internal` | A **strict subdomain** carved out for the tailnet. Bare `internal` would collide head-on with AdGuard's `photos/music/videos/paperless.internal` rewrites, because MagicDNS answers its whole `base_domain` subtree authoritatively. Also has to differ from `server_url`'s domain (module assertion). |
| `override_local_dns` | `false` | `true` would make `10.42.0.1` the resolver for *all* DNS on every joined device, everywhere — nice ad-filtering side effect, but it makes this appliance a hard dependency for a friend's entire internet and a much bigger trust ask. The per-device global takeover, if Tom ever wants it for his own devices only, is `nameservers.split`, not this boolean. |
| `nameservers.global` | `[ "10.42.0.1" ]` | AdGuard, at the address it already binds. |
| `nameservers.split."internal"` | `[ "10.42.0.1" ]` | **The split-DNS entry, now in git.** `modules/adguardhome.nix` describes this as "the admin console's split-DNS entry" — a hand-made row in tailscale.com's web UI. Self-hosting the control plane turns that click into a reviewable line. |

Roaming clients reach `10.42.0.1` through the subnet route this node advertises,
and `:53` on `tailscale0` is already admitted in `modules/adguardhome.nix` — the
same rule for the same reason, no change needed there for this to work.

### No new secret, by construction

The appliance is a recipient of exactly **one** ciphertext
(`huggingface-token`, `secrets.nix` `nasOnly`) and that invariant is untouched.

- headscale's `noise_private.key` is **self-generated** into
  `/var/lib/headscale` on first start. Server-identity state, not a credential
  anyone mints; losing it costs a re-handshake, not data.
- The NAS's own preauth key is **minted at runtime** by
  `headscale-nas-enroll.service`, from the headscale running on the same box,
  into `/run/headscale-nas-enroll/authkey` (0400, root). It never exists at
  rest and never enters git.
- There is deliberately **no** `secrets/tailscale-authkey-nas.age`, and there
  must not be one. `secrets/tailscale-authkey-coordinator.age` and its
  `coordinatorOnly` tier are untouched — that is the emergency rail's key and it
  keeps doing exactly what it already did.

### The cutover unit

`headscale-nas-enroll.service` runs between `tailscaled` and
`tailscaled-autoconnect` and is idempotent:

1. waits for headscale's unix socket (60 s bound);
2. ensures the headscale user `tom` exists;
3. mints a single-use, 1 h, `tag:mesh` preauth key into `/run`, degrading
   through four CLI shapes (json/text × tagged/untagged) so a CLI drift under a
   future headscale bump costs this box a *tag*, not its tailnet identity;
4. reads `tailscale debug prefs`'s `ControlURL` and, if it differs from the
   configured login server, runs a **bounded** `tailscale logout` so
   `tailscaled-autoconnect` re-registers against headscale. Without step 4 the
   migration would silently never happen: a logged-in node is `Running`, and
   `autoconnect` never calls `tailscale up` on a `Running` node.

**Deploy this over the LAN, not over the tailnet.** Step 4 drops this box's
tailscale.com session on purpose. Same register as `nix-on-nvme.nix`'s "never
flip this remotely".

The unit is a oneshot that deliberately does **not** `RemainAfterExit`, so
anything that `Requires=` it re-runs it. That makes

```sh
systemctl restart tailscaled-autoconnect
```

the single recovery command for "this node lost its tailnet identity": it pulls
`headscale-nas-enroll` again, which mints a **fresh** key rather than
re-feeding autoconnect the used, expired one. `RuntimeDirectoryPreserve=yes` is
what keeps `/run/headscale-nas-enroll` alive between the mint and the read.

Manual fallback, if the CLI shape ever drifts (written against **headscale
0.29.3**, `nixpkgs-stable` 26.05 — the NAS is stable-pinned per #135, so this is
the version that actually ships here):

```sh
headscale users create tom
headscale users list                              # note the numeric id
headscale preauthkeys create -u <id> -e 1h --tags tag:mesh
tailscale up --login-server=http://10.42.0.1:8090 --auth-key <key> \
  --ssh --advertise-routes=10.42.0.0/24 --reset
headscale nodes list
headscale nodes approve-routes -i <node-id> -r 10.42.0.0/24
```

Route approval is a real step in phase 1: the day-1 policy carries no
`autoApprovers` (see below for why).

## What is honestly NOT true yet

**headscale is a home-only control plane until phase 2.** There is no Freebox
port-forward and no public DNS name, so nothing off-LAN can register. Until the
`myNas.headscale.publicEndpoint` gate is flipped, the coordinator's
tailscale.com node remains the *only* actual remote-access path. Do not read
"the control plane for everything" off the ruling and assume the roaming half
already works.

## Phase 2 runbook — public exposure (gate OFF)

`myNas.headscale.publicEndpoint.enable`, default off, hostname default
`headscale.mecattaf.dev`, port default `8443`. Flipping it changes `server_url`
from the LAN URL to the public one **including the port**, brings up Caddy on
this box, and admits exactly one door: `wan0 tcp/<port>`.

**This gate is the first deliberate breach of this box's "wan0 admits nothing
unsolicited" invariant**, which is asserted as settled doctrine in two separate
host files (`hosts/nas/tv.nix:117`, `hosts/nas/attic.nix:84`). The doctrine is
being narrowed, not deleted: exactly ONE nonstandard TCP port, terminated by
Caddy, reverse-proxied to a LAN-bound headscale, nothing else on `wan0` changed.
(Ruling 2026-09-01: nonstandard on purpose — nothing else that could ever want
:443 can collide with this door, and a Free line on shared IPv4 doesn't own
:443 anyway. For the record, the coordinator's tailscale.com fallback is
outbound-only NAT traversal and forwards nothing on the Freebox, so there is no
port contention from that side to design around.)

Steps that only Tom can do:

1. **Freebox OS** (`http://mafreebox.freebox.fr`, LAN-side admin):
   - pin a static DHCP lease for the NAS's `wan0` permanent MAC
     (`hosts/nas/a8500.nix`) so the forward target cannot drift;
   - forward **one TCP port — `publicEndpoint.port`, default 8443** — to that
     address. Not :80, not :443. If the panel says the line is on *IPv4
     partagée*, either request full-stack IPv4 there or pick the port from the
     allotted range and set `publicEndpoint.port` to match. **No UDP 3478**:
     embedded DERP stays off.
2. **DDNS**, because the Freebox holds a residential and probably dynamic public
   IP: Freebox DynDNS (`dyndns.freebox.fr`, same admin panel) is the path of
   least resistance; a Cloudflare-API updater is the alternative.
3. **Cloudflare DNS** for the hostname: an A record that is **grey-cloud /
   DNS-only**. Orange-cloud proxying **breaks headscale** — the control channel
   is a `POST` carrying `Upgrade: tailscale-control-protocol`, and Cloudflare's
   proxy does not support that WebSocket-over-POST mechanism. Upstream's own
   documented limitation, not a preference — and it rules out Cloudflare
   Tunnel for the same reason, which is why this runbook forwards a port at
   all.
4. **The ACME secret** (DNS-01; with no :80/:443 there is no other challenge):
   mint a Cloudflare API token scoped to **Zone.DNS edit on mecattaf.dev
   only**, then `nix develop -c agenix -e secrets/cloudflare-dns-acme.age`
   containing the single line `CF_DNS_API_TOKEN=<token>`; add the nasOnly-tier
   entry in `secrets.nix` and the `age.secrets.cloudflare-dns-acme` line in the
   phase-2 block of `hosts/nas/headscale.nix` (it names the runtime path it
   expects; the declarations can't be pre-written because agenix eval requires
   the `.age` file to exist).
5. Flip the gate and deploy. Every already-registered node has to be re-pointed
   once: the NAS does it automatically (the enroll unit sees the stale
   `ControlURL` and cuts over); anywhere else it is one
   `tailscale up --login-server=https://<hostname>:<port> --force-reauth`.
   **Do phase 2 before any friend device joins** — then it costs one node's
   churn instead of everyone's.
6. Verify from off-LAN (phone on LTE): the Tailscale app's custom-server login
   must reach `name:port` and get a valid cert.

**Certs: DNS-01 via `security.acme` (lego), not a caddy plugin.** The first
draft of this page argued for HTTP-01 on :80 to keep a Cloudflare token off
this appliance; the nonstandard-port ruling makes HTTP-01 and TLS-ALPN-01
physically impossible (ACME dials only :80/:443), so DNS-01 is the only
challenge left. The token is an agenix ciphertext scoped to one zone's DNS —
and lego still needs **no `xcaddy` plugin build and no vendor hash**; Caddy
just consumes the minted cert via `useACMEHost`.

Caddy rather than nginx for a load-bearing protocol reason, not taste: nginx and
Apache need explicit `Upgrade`/`Connection` passthrough stanzas to survive
headscale's POST-upgrade; Caddy's `reverse_proxy` handles protocol upgrades
natively. Note Caddy's ACME account has no `email` set — set
`services.caddy.email` at gate-flip time if Let's Encrypt expiry notices are
wanted.

## The friend fleet — designed for, not built today

Full scheme in `hosts/nas/headscale-policy.hujson`'s own header. In brief:

- **One headscale user per PERSON**, never per device. A person's laptop and
  phone group under their own user, which is what makes `<friend>@` a meaningful
  ACL subject.
- **Tag Tom's infrastructure, never a friend's personal device.** `tag:mesh` for
  the NixOS fleet (the same name `modules/secrets.nix` already records for the
  retired tailscale.com authkeys — continuity across the control-plane move, not
  a new idea), `tag:shared` for whatever friends are actually invited to.
  Friends' devices stay untagged personal devices.
- **Deny-all baseline with per-friend narrow grants**, hub-and-spoke: Tom's user
  and `tag:mesh` broad, each friend one explicit grant to `tag:shared` on
  specific ports. Friends never see each other and never see Tom's fleet,
  because nothing grants it.
- **The policy file exists from day one** even though its content is allow-all,
  so the mechanism — policy in git, reviewed in a diff, `systemctl reload
  headscale` to apply — is in place before the first friend key is ever minted.

Day-1 content names **no user and no tag**, on purpose: a policy referencing
`tom@` or `tag:mesh` before those exist can fail validation, and headscale
refuses to serve on a policy it cannot load. On the box that is the house
router, a service that will not start because of an ACL for devices that do not
exist yet is a self-inflicted outage. That is also why `autoApprovers` is a
commented template rather than live config — it depends on an owned tag.

### Key-minting workflow for `omarchy-nix-fleet`

The future public repo holds one agenix-encrypted preauth key per friend device.
Per device:

```sh
# on the NAS
headscale users create <friend>            # once per person
headscale users list                       # numeric id
headscale preauthkeys create -u <id> -e 24h --tags tag:friend-<friend>
# then, wherever the friend-fleet repo lives, encrypt to THAT device's recipients
age -R <recipients-file> -o secrets/tailscale-authkey-<device>.age
```

The device's NixOS config sets
`services.tailscale.extraUpFlags = [ "--login-server=https://<hostname>" ... ]`
and `authKeyFile` at the decrypted path — structurally identical to how
`secrets/tailscale-authkey-coordinator.age` already works in this repo, just in
a different repo with a different recipient set per device. Nothing on the
headscale side needs redesigning for it.

Non-NixOS devices (phones): the ordinary Tailscale app, "use a different server"
/ custom server, then paste a preauth key. Without OIDC there is no browser SSO;
the interactive alternative is `headscale auth register --user <u> --auth-id
<id>` run on the NAS. OIDC is a later option (`oidc.*` freeform settings) and
nothing in today's config precludes it.

## Ops

**State**: `/var/lib/headscale` — `db.sqlite` (+ `-wal`/`-shm`, WAL is on),
`noise_private.key`, `cache/`.

**Backup gap, stated rather than skipped.** `/var/lib/headscale` is on the root
filesystem; `hosts/nas/snapshots.nix` covers exactly six Btrfs subvolumes under
`/mnt/nas`, none of which is this. So the control plane's database is **not
backed up by anything in this repo**. Recorded as a known, accepted gap: the
blast radius of losing it is "every node re-registers", which is cheap and
bounded, and it is emphatically not the irreplaceable-media class the snapshot
schedule exists for. If it ever stops being cheap (friend devices Tom cannot
walk over to), the fix is a timer running `sqlite3 db.sqlite '.backup …'` —
**never** a naive file copy, because WAL mode is on and `db.sqlite` alone is an
inconsistent snapshot.

**Hardening** is the packaged module's stock set and is thorough
(`ProtectSystem=strict`, `ProtectHome`, `PrivateTmp/Devices/Mounts`, full
kernel/proc protections, `UMask=0077`, `NoNewPrivileges`, a
`CapabilityBoundingSet` of just `CAP_CHOWN`). Nothing added.

**Boot ordering**: an `ExecStartPre` waits up to 30 s for `10.42.0.1` to exist on
`enp1s0` before headscale tries its explicit bind — the same race and the same
fix as `modules/adguardhome.nix`'s wait script. Stock `Restart=always/5s` would
eventually win, but a unit that crashloops through the first minute of every
boot is noise on a box whose failure surfacing is supposed to mean something.

## Two hazards this change creates outside this file's lane

1. **`modules/adguardhome.nix`'s hardcoded `100.89.54.51`** — the NAS's
   *tailscale.com*-assigned address, in two places: the `bind_hosts` list
   (line ~110) and the `ExecStartPre` wait-for-address regex (line ~205). Once
   the NAS re-registers against headscale it gets a **different** address out of
   headscale's own `100.64.0.0/10` pool. Left as-is: the wait loop burns its full
   30 s budget every boot, and AdGuard is asked to bind an address that does not
   exist — on the box that is the LAN's only resolver. **The recommended fix is
   not a new literal but deleting the class of bug**: bind only `127.0.0.1` and
   `10.42.0.1`, and let tailnet clients reach `10.42.0.1:53` through the subnet
   route the NAS advertises — which is exactly what headscale's
   `nameservers.global`/`split` now point them at. That removes the last
   hardcoded tailnet IP from the repo.
2. **`flake.nix`** — grepped and reconciled: `nas-topology`'s
   `services.tailscale.enable` / `useRoutingFeatures == "server"` /
   `--advertise-routes` elem asserts (lines 610-613) and
   `fleet-connectivity`'s (1252-1253) all stay **true by design**, because the
   subnet-router role was kept deliberately. The exact-set assert on
   `interfaces.tailscale0.allowedTCPPorts` (1299) is untouched because the new
   doors use `extraInputRules`. What is now **stale prose, not a failing
   assert**, is `nas-topology`'s comment claiming the NAS "does so with an
   interactive login rather than an authkey secret (the NAS holds no secrets —
   `mySecrets.enable = false`)": both halves have been false since 2026-08-28,
   and the login is now runtime-authkey. Worth a comment-only correction in
   whichever commit next touches that check.
