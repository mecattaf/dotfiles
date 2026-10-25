# NAS transport and compute offload — 2026-10-23

Part of #600; umbrella #597; implemented in #607. This is a staging and
acceptance procedure, not authorization to activate, enroll, power off or reboot.

Tom's latest definition supersedes the earlier coordinator-first sequence:
**power off all three NixOS fleet machines together**, move the identified SSDs,
connect the Strix pair with two Thunderbolt 5 cables, and give each Strix its
own Ethernet cable to BE550. Boot the combined generations in their final
roles. The NAS home and agent state must already be staged. Do not depend on
an intermediate coordinator brain boot. Linux **7.3** is the fleet target,
owned by `kernel/linux-7.3`; #607's older parent input still evaluates 7.2.10.
The integration worker must combine that kernel change and the matching
Donnerkeule work with #605–#610 before qualifying the final generation.

## One enrollment and non-expiry mechanism

Use **interactive user enrollment plus the official Tailscale admin console**
for the three tailnet nodes. Reuse each node's existing identity and persistent
state; do not create tagged service identities or distribute an auth key.
There is no API/OAuth credential to provision and no periodic
reauthentication job. The nodes are `client`, `nas` and `strix-coordinator` in
`tail8dd1.ts.net`, on the official tailscale.com control plane. Do not copy
one machine's Tailscale state to another or run two daemons over one identity.

`modules/fleet-transport.nix`, imported by `common.nix`, enables this policy
automatically for those three exact hostnames. **`strix-worker` is not on the
tailnet** (Tom, 2026-10-25: "worker's tailnet login: fine, and i was thinking
let's not"): `hosts/strix-worker/default.nix` sets
`services.tailscale.enable = false`, so it runs no `tailscaled` and no
`tailscaled-set`, and the NAS reaches it over the house LAN at 10.42.0.5.
Compute remains free of operator secrets.

The target is vanilla (Tom, 2026-10-25: "default vanilla, make it work"):

| Node | Advertises | Selects | DNS | Local state to preserve on its final root |
| --- | --- | --- | --- | --- |
| NAS | Exit node; `10.42.0.0/24` | No exit node; no imported subnet routes | `--accept-dns=false` (it is the LAN resolver) | `/var/lib/tailscale-personal/tailscaled.state` |
| Client | Nothing | No exit node (D-55); subnet routes | `--accept-dns=true` (MagicDNS) | `/var/lib/tailscale/` |
| Coordinator | Nothing | No exit node; no subnet routes | `--accept-dns=false` | `/var/lib/tailscale/` |
| Worker | Not on the tailnet | — | — | — |

All use `--ssh=false` and keep ordinary OpenSSH. NAS forwarding/NAT remains
declared by `router.nix` and Tailscale's server routing feature. NAS reaches
the internet through BE550; it cannot select itself as an exit. Native tailnet
peer connections can remain direct.

**The NAS is the only exit node, and no host selects it.** Tom: "i think the
NAS is the right exit-node, instead of it being from the coordinator". The
Zenbook (client) selects no exit node on any network (D-55 "no-exit-client"):
its internet goes out through whichever Wi-Fi it is on, so a NAS outage leaves
the Freebox rung of its Wi-Fi ladder usable. Tom can pick the NAS exit by hand
on the go (`tailscale set --exit-node=nas`, undone with `--exit-node=`); the
next boot's `tailscaled-set` clears it again. The client accepts
`10.42.0.0/24` through the tailnet when roaming and keeps MagicDNS: resolved
keeps the Wi-Fi DNS as its default route and sends only `tail8dd1.ts.net` to
100.100.100.100, so `nas.tail8dd1.ts.net` resolves at home and away.

**strix-coordinator is the independent recovery box.** Tom: "strix
coordiantor having its own tailscale login allows us to do the recovery
process, exaclty like what happened tonight (we had a NAS issue, the strix
coordinator working on freebox saved the day)". It keeps its own login and
the node name `strix-coordinator`, selects no exit node and accepts no routes,
so its internet goes straight through the BE550 and its tailnet path does
not depend on the NAS. Its LAN profile keeps the 2500 rule that holds
`10.42.0.0/24` on the main table, as a guard against a hand
`tailscale set --accept-routes`.

### Which host serves what on the tailnet

The coordinator is pure compute and the NAS is the brain, so every tailnet
front door is on the NAS:

| Service | Tailnet address | Declared in |
| --- | --- | --- |
| Herdr web UI | `https://nas.tail8dd1.ts.net/` (private Serve :443 → 127.0.0.1:7317) | `modules/herdr-web-ui.nix`, `hosts/nas/agent-host.nix` |
| Immich (photos) | `http://nas.tail8dd1.ts.net:2283` | `hosts/nas/media.nix`, `hosts/nas/tailscale.nix` |
| Navidrome (music) | `http://nas.tail8dd1.ts.net:4533` | `hosts/nas/media.nix`, `hosts/nas/tailscale.nix` |
| Plex (videos) | `http://nas.tail8dd1.ts.net:32400/web` | `hosts/nas/media.nix`, `hosts/nas/tailscale.nix` |

The old `strix.tail8dd1.ts.net` name went with the strix -> strix-coordinator
rename, so roaming apps that still name it must use the NAS addresses above
(or `http://nas:<port>` through the subnet route). The coordinator's old
Serve on `strix.tail8dd1.ts.net:8443` (a Herdr web UI on 127.0.0.1:7318 from
its retired operator seat) is not declared anywhere and is removed from its
Tailscale state. The coordinator's socket relays (2283/4533/32400) and its
`.internal` Caddy names stay as LAN-only front doors. `navidrome-scan` runs on
the NAS, where its credentials are, and dials `http://nas:4533`.
`tests/fleet-agent-transport` asserts each of these.

Tom's hands and credentials, during the supervised staging window:

1. Authenticate as the tailnet owner/admin in the
   [Machines console](https://login.tailscale.com/admin/machines), including
   identity-provider MFA. Existing nodes need no new login if their state is
   valid. For a genuinely fresh node, run
   `sudo tailscale login --login-server=https://controlplane.tailscale.com` on that
   staged node and authenticate its URL as Tom, then approve the machine if
   device approval or Tailnet Lock is enabled. Never enroll using copied
   state from another node. The worker is not enrolled at all. These actions
   were not run by this task. The preserved NAS state is an intentional
   startup condition; an absent file blocks its daemon rather than silently
   enrolling a new NAS.
2. On each final identity, set its unique name to the table's name, open its
   ellipsis menu and choose **Disable Key Expiry**. Record each device's stable
   ID, name and **Key expiry disabled** state in the integration receipt.
   Disabling expiry belongs to the control plane; Nix flags cannot do it.
   Repeat after any replacement/re-enrollment. A key that merely expires far
   in the future does not pass. Console login expiry is a separate setting.
3. On NAS's machine entry approve `10.42.0.0/24` under route settings and
   **Use as exit node** under exit-node settings. Ensure the existing tailnet
   policy allows Tom's three nodes to reach each other, the house subnet, and
   `autogroup:internet` via the exit node; retain unrelated policy entries.
   Also enable the tailnet HTTPS certificate facility if not already enabled
   for the declared private `tailscale serve` UI. Funnel is unnecessary.
4. Apply the reviewed per-node preferences in the supervised staging window.
   Nix's `tailscaled-set` unit applies the exact `extraSetFlags` at normal boot;
   it does not log in. For a node enrolled before those units are staged,
   use the same complete flag set with `sudo tailscale set`:

   ```sh
   # NAS only
   sudo tailscale set --hostname=nas --accept-dns=false --ssh=false --advertise-routes=10.42.0.0/24 --advertise-exit-node --accept-routes=false
   # strix-coordinator (recovery box: no exit node, no routes; the empty value clears an exit node)
   sudo tailscale set --hostname=strix-coordinator --accept-dns=false --ssh=false --accept-routes=false --exit-node=
   # The client (roaming: subnet routes and MagicDNS, no exit node)
   sudo tailscale set --hostname=client --accept-dns=true --ssh=false --accept-routes=true --exit-node=
   ```

   The unit first waits, bounded at 120 s, for `BackendState` Running with
   the NAS node in `tailscale status --json`, so the set never races
   tailscaled's start (an earlier `--exit-node=nas` failed there before the
   netmap arrived); on a timeout, or a node that needs a login, it runs the
   set anyway and the set reports its own error. Do not
   use `--reset`, reset Serve/Funnel, log out, delete state or change live
   routes as an experiment.
5. Run the declared **read-only** `fleet-transport-check` on each staged node.
   It queries `tailscale status --json`, checks the three exact DNS identities
   in this tailnet, online state, no reported expiry, visible NAS exit/subnet
   approval and that no exit node is selected. It returns nonzero on an incomplete
   view. A saved status can be checked with `--status FILE`. Record console
   expiry receipts too: absent `KeyExpiry` alone is not an independent
   control-plane audit. If this Tailscale version omits route fields, retain
   the failed observation and verify in the console; do not call it a pass.
6. From a roaming client network, verify NAS SSH, private Herdr HTTPS
   (`https://nas.tail8dd1.ts.net/`), a LAN-only service through
   `10.42.0.0/24`, and SSH to `strix-coordinator` over the tailnet. On the LAN
   verify both Strix SSH paths and BE550 reachability. A status
   parser cannot prove packet forwarding, ACLs, DNS, MTU or throughput.

These steps require **Tom's existing admin/SSO login and root access on each
staged node**, not a new reusable secret. Console route approval, HTTPS and
non-expiry remain open until recorded. Enrollment/persistent state must be on
each final root before the simultaneous power-off, or the fleet is not ready
for unattended first boot. Do not infer this from a closure build.

References: [node key expiry](https://tailscale.com/docs/features/access-control/key-expiry),
[exit-node approval and use](https://tailscale.com/docs/features/exit-nodes),
[subnet route approval](https://tailscale.com/docs/features/subnet-routers).

## NAS sessions, remote builds and heavy commands

Herdr, Claude Code (`cc`, `cc2`), Codex and dsh run on NAS; dsh placement and
its Gufo provider come from #609. The client projector/picker defaults now
target NAS. `desk` on NAS opens local Herdr; on other machines it projects NAS.
Herdr's keep-old, OOMPolicy=continue and oomd exclusion remain in force.
Claude seats and Codex share `home/agent-runtime-rules.md`; #609 also gives
it to dsh. That policy directs heavy commands off NAS. It is agent guidance,
not an OS mechanism that intercepts arbitrary shell commands.

`modules/agent-offload.nix` declares NAS `nix.distributedBuilds = true`,
`max-jobs = 0`, and two `ssh-ng` builders: `tom@strix-coordinator` and
`tom@strix-worker`, two concurrent jobs each, using substitutes. Nix returns
outputs to NAS's store; NAS still performs evaluation, fetching, closure
storage and lightweight orchestration. An unavailable builder causes waiting
or failure, never permission to compile heavy closures locally. Do not pass
`--max-jobs` to override NAS's setting.

The daemon and `fleet-exec` use the delivered NAS `/run/agenix/ssh-user-key`.
No private SSH/GitHub key is delivered to compute; the existing mesh public
key authorizes incoming `tom` logins and `@wheel` is already trusted by Nix.
The SSH configuration maps the two names to Ethernet `.2` and `.5`, with
BatchMode, StrictHostKeyChecking and no agent forwarding. Coordinator's key
is pinned; **worker's host key is still absent in #608**. Tom must obtain its
public key from the staged install through a trusted path and commit it in
`mesh-registry.nix`. `ssh-keyscan` without independent verification does not
qualify it. An empty key is never accepted automatically. This is a remaining
offload gate, not a fabricated successful connection.

Before a build, check `df -h /` on its actual compute host and stop below
25 GB available. For other heavy commands, first stage a non-secret checkout
on the chosen compute host, then run, for example:

```sh
fleet-exec strix-worker --cwd /home/tom/build/project -- make -j4
fleet-exec strix-coordinator --cwd /home/tom/build/project -- /home/tom/.local/bin/runtime-test -- ./test-runtime
```

Use a remote absolute runtime-test path: a local shell would expand `~`
before SSH. The helper requires an explicit existing remote cwd, quotes each
argument, checks
host identity and propagates SSH/command failures without local fallback. It
does not synchronize a checkout or export NAS credentials. The final #608 worker profile uses `rawDotfiles.inStore = true`, like the
client, so its helpers do not depend on a checkout at first boot. Coordinator
still needs `/home/tom/mecattaf/dotfiles` at the reviewed revision for its raw
helpers and activation guard. Stage that checkout without NAS auth directories. Private inputs
are fetched by the authenticated NAS agent and sent as source/closure data;
do not copy its auth directories to compute. Raw dotfiles on NAS still require
`/home/tom/mecattaf/dotfiles` at the combined reviewed revision.

For the private web UI, use the authenticated `gh api .../tarball/<rev>`
prefetch/hash-check/`nix-store --add-fixed` recipe in #607. The source pin is
`e85ffd1ff0402e3aee9c2df6ec47e7cafefe7d60`, hash
`sha256-F/HeC2E4eIR4EOCMIpTbWTZWbD4DMBM5Biqrl4Vb2TQ=`; expected source path is
`/nix/store/bvpscg7accqw4dl1m47mjmkrrxhhh9dj-source`. Tonight it was prefetched
and built on coordinator. For a cold NAS-orchestrated build, the same light
archive prefetch can run under NAS's existing authenticated GitHub CLI before
calling Nix. Alternatively copy that verified store path from coordinator to
NAS first. Nix sends source inputs to the selected builder; it never sends
GitHub credentials. Neither worker nor the NAS Nix daemon needs a new GitHub
token. Without that cache preparation the private fetch can fail; a shell's
`gh` login is not automatically inherited by a multi-user Nix daemon.

`/etc/local-model.json`, `LOCAL_MODEL_ENDPOINT` and the request-scoped
`utility-model` name **Gufo `http://strix-coordinator:8731`**, served model
`qwen3.8-flash-next`. There is no model server on NAS. #610 owns the dual-host
RDMA engine, shared service token and rail qualification on Linux 7.3. Its
current TP2 service is manual-only pending qualification; a declared NAS
client cannot prove dual-host inference or automatic TP2 boot readiness.

## Evidence and remaining handover gates

The `fleet-agent-transport` check evaluates exact server/consumer routing,
absence of auth keys, both remote builders, zero NAS local build slots,
strict SSH and Gufo client settings. Its fixture tests reject missing/offline
identities, reported key expiry, wrong tailnet, wrong exit node and missing
route approvals. They also test hostile argv/cwd quoting and failure
propagation without starting SSH, Herdr or a user manager.

The renamed compute tests on #607's parent are **role/name fixtures**; the
check automatically uses real named compute configurations once #608 is merged. The
integration worker must check the actual #608 configurations, build all
final Linux 7.3 generations and preserve #606's serial-bearing by-id home path and serial guard. The
production NAS configuration needs no PARTUUID and no filesystem override.

`tests/fleet-agent-transport/integration.nix` inspects the combined production
`flake` directly. It applies no kernel, module, filesystem or transport
overrides. Its facts and check do not qualify the actual final SSD,
enrollment or remote hardware.

Before telling Tom to unplug, integration still needs the real SSD/partition
mapping and staged final boot entries, NAS home/databases/raw checkout and
both Claude seat histories, Tom's 18-file rekey, verified worker SSH key,
the three console non-expiry/enrollment receipts and the final production
builds. The worker needs no tailnet enrollment.

Actual exit/subnet forwarding, both remote builder jobs, and #610's
two-cable/RDMA/Gufo qualification belong to supervised hardware acceptance.
They cannot be proved by the pre-hardware fixtures. #610's manual-only TP2
unit also needs its eventual boot policy settled to meet "everything comes
up"; #607 does not silently start or qualify it. Power-off cannot preserve
live PTY processes: save/resume
records deliberately and verify recoverable sessions and their original
working directories before releasing the physical move.
