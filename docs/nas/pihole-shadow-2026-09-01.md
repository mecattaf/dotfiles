# Pi-hole in shadow mode on the NAS (2026-09-01)

Tom's ruling, 2026-09-01: *"Pi-hole gets added on the NAS in SHADOW MODE:
evaluation only — own DNS port and web UI, actively resolving/filtering for
testing, but NOT advertised to any client (DHCP/DNS advertisement
unchanged)."*

The Nix file that decides all of this is `hosts/nas/pihole.nix`, gated by
`myNas.piholeShadow.enable` in `hosts/nas/default.nix`. This page is the
comparison runbook and the promotion/retirement criteria; it does not restate
what the module's own header already argues.

## Topology

    LAN client ──DHCP option 6──> 10.42.0.1:53   AdGuard Home   THE resolver
                                                 (modules/adguardhome.nix)
                    dns_hijack DNAT drags :53 stragglers here too
                                                 (hosts/nas/router.nix)

    coordinator ──dig -p 5335──> 10.42.0.1:5335  Pi-hole FTL 6.7  the challenger
    (10.42.0.2, the only                         (hosts/nas/pihole.nix)
     admitted source)

    tom@anywhere ─ssh -L─> 127.0.0.1:5336        Pi-hole dashboard, loopback only

| | AdGuard Home | Pi-hole FTL (shadow) |
|---|---|---|
| DNS port | 53 | **5335** |
| DNS bind | `127.0.0.1`, `10.42.0.1`, tailnet addr | wildcard, `listeningMode = LOCAL` |
| Admitted from | whole LAN (`iifname enp1s0`) + tailscale0 | **`ip saddr 10.42.0.2` only** |
| Web UI | `127.0.0.1:3000`, no password | `127.0.0.1:5336`, no password, ACL `+127.0.0.1,+[::1]` |
| Upstreams | DoH to 1.1.1.1 / 1.0.0.1 / 9.9.9.9 | **plaintext Do53** to the same three |
| DHCP | dnsmasq, unchanged | off, asserted |
| NTP | n/a | off (server *and* clock sync), asserted |
| Config source | git, `mutableSettings = false` | git, store symlink + `misc.readOnly` |
| Query retention | AdGuard default | `database.maxDBdays = 14` |

Nothing about any client changes. No phone URL, no `option:dns-server`, no
`.internal` rewrite, no `resolved` upstream. That is the entire point.

## Access

    ssh -L 5336:127.0.0.1:5336 nas       # then http://127.0.0.1:5336

The dashboard's `webserver.domain` is `pihole-shadow.internal`, which resolves
**nowhere on purpose** — the `.internal` rewrites live in
`modules/adguardhome.nix`, and adding one for the shadow instance would be the
first step of promotion, not of evaluation. Browse by the loopback address.

There is no password, exactly as AdGuard has no password here: an empty
`webserver.api.pwhash` means Pi-hole v6 requires no login, and access control is
the loopback bind plus the in-process ACL plus (for DNS) one nftables source
address. See "If a login gate is ever wanted" below.

## Driving the comparison

Both resolvers answer from the same three upstreams and read the same two
blocklist URLs, so a verdict difference is the filter.

**Same-question diff, from the coordinator** — the shape of the comparison; run
it over a real domain sample (the coordinator's own browser history, or
AdGuard's top-queried list from its query log) rather than a handful of
hand-picked names:

    for d in $(cat domains.txt); do
      a=$(dig +short -p 53   @10.42.0.1 "$d" | head -1)
      p=$(dig +short -p 5335 @10.42.0.1 "$d" | head -1)
      [ "$a" = "$p" ] || printf '%-40s adguard=%-16s pihole=%s\n' "$d" "${a:-NXDOMAIN}" "${p:-NXDOMAIN}"
    done

AdGuard's default blocked answer and Pi-hole's `blocking.mode = "NULL"` both
resolve to `0.0.0.0`, so "blocked on both" shows as agreement and only genuine
disagreement prints.

**List coverage, before believing any blocked-percentage number:**

    pihole -q example.com              # is it on a list, and which one
    sudo -u pihole "$(nix build --no-link --print-out-paths \
      nixpkgs#pihole-ftl)"/bin/pihole-FTL sqlite3 /var/lib/pihole/gravity.db \
      'select adlist_id, count(*) from gravity group by adlist_id;'

The `pihole` CLI is on `PATH` on the NAS — the upstream module installs a wrapper
that re-execs as the `pihole` user. `pihole-FTL` itself is not, and no `sqlite3`
is installed on this box; FTL ships its own (`pihole-FTL sqlite3`), reached
above from the store rather than by adding a package to the appliance for one
ad-hoc query. `gravity.db` and `pihole-FTL.db` are mode 0700 under the `pihole`
user, hence the `sudo -u`.

Compare that against AdGuard's own rule counts in its UI. The two instances
read the *same URLs* but not the same *rules*: `filter_1.txt` is AdGuard/ABP
syntax, and Pi-hole's gravity ingests only its plain `||domain^` subset,
skipping everything with modifiers or regex. Pi-hole's effective list from that
URL is therefore a strict subset of AdGuard's, and a lower block rate is partly
that and not necessarily worse filtering. Steven Black is a plain hosts file and
imports whole on both sides.

**Volume and latency:** Pi-hole's dashboard and
`/var/lib/pihole/pihole-FTL.db` carry per-query detail at `privacyLevel = 0`.
The plaintext `pihole.log` is deliberately OFF — upstream's logrotate rule
covers `FTL.log` only, so that log would grow unbounded on an appliance whose
disk siting has already cost one incident
(`emmc-relief-2026-08-22.md`). Nothing needed for the comparison lives there.

**What to actually decide on**, in descending weight:

1. False positives. A filter that breaks one thing the household uses loses,
   whatever its block rate. Both sides' query logs name the matching rule.
2. Block rate on the same domain sample, *adjusted* for the ABP-subset effect
   above.
3. Operability on THIS box: does the config stay in git without fighting the
   product (Pi-hole is unconditionally declarative on NixOS — there is no
   `mutableSettings` equivalent, `/etc/pihole/pihole.toml` is always a store
   symlink), and does per-client policy exist for the things this house wants.
4. Transport. This is where the shadow instance is structurally behind, and it
   is not a small point — see below.

## The transport asymmetry is a promotion blocker, not a footnote

FTL 6.7 has no native DoH/DoT: this pin's `pihole.toml` documents `upstreams`
as "IP addresses and/or hostnames, optionally with a port (`#...`)" and nothing
else. So the shadow instance talks **plaintext Do53** to 1.1.1.1 / 1.0.0.1 /
9.9.9.9 while AdGuard talks DoH to the same three.

That is fine for measuring *filtering* and unacceptable as a resolver posture:
encrypted upstreams are why `modules/adguardhome.nix` uses IP-literal DoH at
all, and this box drops the LAN's own DoT/DoH bypass attempts
(`nftables.tables.dns_hijack`) specifically so every household lookup goes out
encrypted. Promoting Pi-hole as configured would hand the ISP the whole house's
DNS back.

Pointing FTL at AdGuard (`127.0.0.1#53`) to borrow its DoH was rejected: AdGuard
would filter first and Pi-hole would never see anything left to block, which
destroys the only measurement the instance exists to take.

## If a login gate is ever wanted

Not built, and not needed for evaluation. The door, if it is ever opened:

`services.pihole-ftl.settings` renders through `pkgs.formats.toml` into a
**world-readable Nix store path**, so an inline `webserver.api.pwhash` is
theatre regardless of `/etc/pihole/pihole.toml` being mode 400. The safe form is
FTL's environment override, read by PID 1 before the `User=pihole` drop:

1. Generate the hash off-box (Pi-hole's own balloon-hash scheme; `pihole -a -p`
   in a throwaway shell with the same `pkgs.pihole` derivation — NOT on the NAS,
   where `misc.readOnly = true` blocks the CLI write path by design).
2. `printf 'FTLCONF_webserver_api_pwhash=<hash>\n'` into
   `secrets/pihole-admin-env.age` via `nix develop -c agenix -e
   secrets/pihole-admin-env.age` — **Tom only, the admin age key is the sole
   editor**.
3. Add it to the `nasOnly` tier in `secrets.nix` (the tier
   `huggingface-token.age` already uses, whose comment invites exactly this:
   "add its key back here for the specific secrets it consumes, not
   wholesale"), and a host-gated `pathExists`-guarded delivery block in
   `modules/secrets.nix`.
4. `systemd.services.pihole-ftl.serviceConfig.EnvironmentFile =
   [ config.age.secrets.pihole-admin-env.path ];`

`mySecrets.enable` is already true on the NAS, so this costs one ciphertext and
no new machinery — but it also makes the NAS a recipient of a second secret,
which `hosts/nas/default.nix:54-70` treats as a decision, not a detail.

## Promotion — what it would actually entail

Promotion is not a flag. In dependency order:

1. **Solve the transport problem** or explicitly accept plaintext upstreams:
   a `cloudflared` / `dnscrypt-proxy` front for FTL, or Unbound as a local
   recursive resolver, on this same box. This is the largest piece and it is
   new code, not a setting.
2. **Move :53.** AdGuard and Pi-hole cannot share it. That means AdGuard's
   `bind_hosts` (loopback + `10.42.0.1` + the tailnet/headscale address), its
   boot-race `ExecStartPre` wait loop, and the `tailscale0` DNS door all move to
   Pi-hole equivalents — and Pi-hole has no `filtering.rewrites`: the four
   `.internal` names become `dns.cnameRecords` / `dns.hostRecord` entries, which
   is a different mechanism with different semantics, not a rename.
3. **Re-point `resolved`.** `services.resolved.settings.Resolve.DNS =
   "127.0.0.1"` also lives in `modules/adguardhome.nix`. It is written
   ungated, but that module is imported by the NAS alone today (`flake.nix`
   asserts `!coordinator.services.adguardhome.enable` and the same for the
   worker — per-device AdGuard is FORBIDDEN on this LAN, its DoH upstreams
   being exactly what `dns_hijack` drops), so this is one host's line to move,
   not the fleet's. The module's own header still describes the older
   NAS+coordinator arrangement; do not read it as current.
4. **Nothing changes for clients.** DHCP option 6 and the `dns_hijack` DNAT
   both name `10.42.0.1`, which is this box either way. That is the one part of
   a promotion that is free.
5. **Invert the tripwires.** The seven assertions in `hosts/nas/pihole.nix`
   encode "AdGuard owns :53, Pi-hole is not advertised". They must be rewritten,
   not deleted — and `flake.nix`'s `nas-topology` AdGuard asserts (`enable`,
   `bind_hosts` contains `10.42.0.1`, never `0.0.0.0`) move with them.
6. **Decide the web UI's exposure and password** for real (see above), because a
   promoted resolver's dashboard is operational, not exploratory.

## Retirement

    myNas.piholeShadow.enable = false;   # hosts/nas/default.nix

That is the whole procedure — no client ever depended on it, which was the
design. Afterwards, delete `hosts/nas/pihole.nix`, its import line, and this
page in one commit; `/var/lib/pihole` and `/var/log/pihole` are stateful leftovers
to remove by hand (`rm -rf`), the same way every other retired service's state
has been.

## Deliberately not done

- **No AdGuard changes of any kind.** `modules/adguardhome.nix`,
  `hosts/nas/router.nix` and the DHCP/DNAT path are untouched by this work; the
  AdGuard improvement pass is a separate change landing the same day.
- **No `pi.hole` / `pihole-shadow.internal` rewrite.** See "Access".
- **No LAN or tailnet door.** :5335 from the coordinator, :5336 from loopback,
  nothing else. A phone must not be able to reach the shadow resolver even by
  accident.
- **No `nix flake check` assertions.** The invariants live as module `assertions`
  in `hosts/nas/pihole.nix` instead, so they travel with the file that creates
  them and die with the gate rather than outliving it as stale asserts naming
  attributes that no longer exist — the exact failure `flake.nix:700-710`
  records for the retired `/30` admissions.
