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
for all four nodes. Reuse each node's existing identity and persistent state;
do not create tagged service identities or distribute an auth key. There is
no API/OAuth credential to provision and no periodic reauthentication job.
The nodes are `client`, `nas`, `strix-coordinator`, and `strix-worker` in
`tail8dd1.ts.net`, on the official tailscale.com control plane. Do not copy
one machine's Tailscale state to another or run two daemons over one identity.

`modules/fleet-transport.nix`, imported by `common.nix`, enables this policy
automatically for those four exact hostnames. **#608 must remove its worker's
`services.tailscale.enable = lib.mkForce false`**. Its former coordinator
fallback flag list is superseded by the shared policy. Compute remains free
of operator secrets. The old `strix` name on #607's stacked parent is left
alone; the real renamed hosts get the new policy on integration.

| Node | Advertises | Selects | Local state to preserve on its final root |
| --- | --- | --- | --- |
| NAS | Exit node; `10.42.0.0/24` | No exit node; no imported subnet routes | `/var/lib/tailscale-personal/tailscaled.state` |
| Client | Nothing | NAS exit; subnet routes; LAN access allowed | `/var/lib/tailscale/` |
| Coordinator | Nothing | NAS exit; subnet routes; LAN access allowed | `/var/lib/tailscale/` |
| Worker | Nothing | NAS exit; subnet routes; LAN access allowed | Fresh, independently enrolled `/var/lib/tailscale/` |

All use `--accept-dns=false --ssh=false`: keep existing DNS and ordinary
OpenSSH. NAS forwarding/NAT remains declared by `router.nix` and Tailscale's
server routing feature. NAS reaches the internet through BE550; it cannot
select itself as an exit. Native tailnet peer connections can remain direct.
Internet exit and access from outside the house to the LAN use NAS; this does
not force peer-to-peer SSH or RDMA packets through it. With NAS unavailable,
exit traffic fails closed; the Strix Ethernet underlay still reaches BE550
for Tailscale transport/control and the explicit LAN exception retains LAN
access. No automatic exit-node bypass is installed.

Tom's hands and credentials, during the supervised staging window:

1. Authenticate as the tailnet owner/admin in the
   [Machines console](https://login.tailscale.com/admin/machines), including
   identity-provider MFA. Existing nodes need no new login if their state is
   valid. For a genuinely fresh node, run
   `sudo tailscale login --login-server=https://controlplane.tailscale.com` on that
   staged node and authenticate its URL as Tom, then approve the machine if
   device approval or Tailnet Lock is enabled. Do this separately for worker;
   never enroll using copied coordinator state. These actions were not run
   by this task. The preserved NAS state is an intentional startup condition;
   an absent file blocks its daemon rather than silently enrolling a new NAS.
2. On each final identity, set its unique name to the table's name, open its
   ellipsis menu and choose **Disable Key Expiry**. Record each device's stable
   ID, name and **Key expiry disabled** state in the integration receipt.
   Disabling expiry belongs to the control plane; Nix flags cannot do it.
   Repeat after any replacement/re-enrollment. A key that merely expires far
   in the future does not pass. Console login expiry is a separate setting.
3. On NAS's machine entry approve `10.42.0.0/24` under route settings and
   **Use as exit node** under exit-node settings. Ensure the existing tailnet
   policy allows Tom's four nodes to reach each other, the house subnet, and
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
   # Each of client, strix-coordinator, strix-worker, with its own hostname
   sudo tailscale set --hostname=strix-worker --accept-dns=false --ssh=false --accept-routes=true --exit-node=nas --exit-node-allow-lan-access=true
   ```

   The hostname `nas` must resolve to the approved NAS node in the tailnet
   map before selecting it. Do not use `--reset`, reset Serve/Funnel, log out,
   delete state or change live routes as an experiment.
5. Run the declared **read-only** `fleet-transport-check` on each staged node.
   It queries `tailscale status --json`, checks four exact DNS identities in
   this tailnet, online state, no reported expiry, visible NAS exit/subnet
   approval and the selected exit ID. It returns nonzero on an incomplete
   view. A saved status can be checked with `--status FILE`. Record console
   expiry receipts too: absent `KeyExpiry` alone is not an independent
   control-plane audit. If this Tailscale version omits route fields, retain
   the failed observation and verify in the console; do not call it a pass.
6. From a roaming client network, verify NAS SSH, private Herdr HTTPS, a
   LAN-only service through `10.42.0.0/24`, and internet egress through NAS.
   On the LAN verify both Strix SSH paths and BE550 reachability. A status
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
does not synchronize a checkout or export NAS credentials. The checked #608
compute profiles also use `rawDotfiles.inStore = false`, so both Strix hosts
need `/home/tom/mecattaf/dotfiles` at the reviewed revision for their helpers
and activation guard. Stage that source checkout without NAS auth directories;
the client alone uses in-store raw dotfiles. Private inputs
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
integration worker must check the actual #608 configurations, remove its
worker disable, build all final Linux 7.3 generations and preserve #606's
real NAS home PARTUUID guard. A synthetic filesystem UUID proves only that
an otherwise combined closure can build; never boot that fixture.

`tests/fleet-agent-transport/integration.nix` accepts the combined `flake` and
an optional `kernelPackages` argument to inspect this additive transport
change without editing another worker's checkout. Its default `facts` retain
the real assertion failures. Explicit `diagnostic = true` emulates removing
the worker disable and uses the invented NAS home PARTUUID; its `check` and
`nasBuildFixture` qualify code/build compatibility only. They do not qualify
the final SSD or supply a production-ready generation.

Before telling Tom to unplug, integration still needs the real SSD/partition
mapping and staged final boot entries, NAS home/databases/raw checkout and
both Claude seat histories, Tom's 18-file rekey, verified worker SSH key,
all four console non-expiry/enrollment receipts and the final production
builds. If worker cannot be enrolled before the move, its first boot needs
Tom's interactive login and console steps; that is an explicit remaining
hands-on step, not unattended tailnet readiness.

Actual exit/subnet forwarding, both remote builder jobs, and #610's
two-cable/RDMA/Gufo qualification belong to supervised hardware acceptance.
They cannot be proved by the pre-hardware fixtures. #610's manual-only TP2
unit also needs its eventual boot policy settled to meet "everything comes
up"; #607 does not silently start or qualify it. Power-off cannot preserve
live PTY processes: save/resume
records deliberately and verify recoverable sessions and their original
working directories before releasing the physical move.
