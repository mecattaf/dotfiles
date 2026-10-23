# October 23 cutover — production stack on Linux 7.3

This supersedes the earlier 7.2.12 integration proof at `2792cf58`. The rebuilt
stack uses #611 instead of #583 and the final heads supplied by Tom. All four
**production** configurations evaluate and build on Linux 7.3. The NAS now
mounts its serial-bearing by-id p2 path; no PARTUUID option, invented UUID,
filesystem override or transport override is used in this proof.

**This is build readiness, not the instruction to unplug.** The disk/install,
identity, credential and hardware gates below remain. In particular the
current four-rail Donnerkeule configuration excludes the old USB4 IP/stream
drivers, and TP2 is still manual-only.

No deployment, boot staging, installation, partitioning, filesystem mount,
reboot, service control, module load, secret decryption/rekey or model borrow
was performed. The live Strix remains on 7.2.10 with its sessions intact.

## Exact integration

Base: `7a794a5ea955f3c20dac70f5a8b0f6425f929427` (`origin/main`).
Tested source: `b1fef43c4e0a3c75407666ce88b49a1136f66b7d`.
The following evidence commit adds only this report and its JSON companion.

| Order | PR | Branch | Fetched and tested head |
| --- | --- | --- | --- |
| 1 | #575 | `rules/ultracode-light-verify` | `f501e856` |
| 2 | #611 | `kernel/linux-7.3` | `269f8eeb` |
| 3 | #605 | `gufo/retire-halogen-oct23` | `af8f4811` |
| 4 | #604 | `fleet/roles` | `4b260c69` |
| 5a | #608 | `fleet/strix-coordinator-worker` | `2e64db80` |
| 5b | #607 | `nas/agent-host` | `4997de0e` |
| 5c | #606 | `nas/home-disk` | `826d63ce` |
| 6 | #609 | `dsh/nas-placement` | `15e0c550` |
| 7 | #610 | `compute/donnerkeule-gufo-rdma` | `5735ec2d` |

These were recombined from main, with a separate merge for each branch in this
order. `0edad97b` then records the previous inspection history as a parent while
retaining the freshly rebuilt 7.3 tree. This preserves the published branch's
history without carrying forward its 7.2 kernel or NAS fixture. No force-push
is needed. No worker branch or PR was changed, and this branch is not a PR to
merge. The fetched heads were checked again before delivery.

## Production build results

| Host | Evaluates | Full toplevel builds | Selected kernel | Target role |
| --- | --- | --- | --- | --- |
| strix-coordinator | Yes | Yes | 7.3 | Compute |
| strix-worker | Yes | Yes | 7.3 | Compute |
| NAS | Yes | Yes | 7.3 | Router, canonical home, agent host and transport |
| client | Yes | Yes | 7.3 | Physical seat |

All four select the exact same kernel derivation:
`/nix/store/jbib9wp36fjfr6x8v8hhp3f0p110b4ak-linux-7.3.drv`.
The module ABI/release is **7.3.0**. NAS stable userspace remains separate from
the current fleet kernel.

`tests/cutover-integration/default.nix` reads the actual configurations and
asserts the shared kernel/module derivations and the absence of a NAS
`partUuid` option. `tests/fleet-agent-transport/integration.nix` now likewise
reads production configurations directly; its obsolete diagnostic fixture was
removed. Exact derivations, output paths, commands and receipts are in
`cutover-integration-2026-10-23.json`.

The production NAS home mount is:
`/dev/disk/by-id/nvme-WD_BLACK_SN7100_500GB_260538801482-part2`, with
`subvol=@home`, and `user@1000.service` requires `/home`. The snapshot mount
uses the same disk's `@snapshots`. A missing disk keeps the router bootable
while preventing the user manager from starting against an empty eMMC home.
This build does not prove that the physical disk has been prepared or copied.

## What the combined configuration proves

- **Transport:** Tailscale is enabled on all four exact hostnames, without a
  delivered auth key. NAS advertises the exit node and `10.42.0.0/24`; client
  and both compute hosts select NAS with LAN access allowed. Ordinary
  OpenSSH remains the transport. Non-expiry is a control-plane operation,
  not something a Nix build can set or verify.
- **NAS offload:** Herdr, Claude/Codex tooling and dsh are placed on NAS.
  Herdr retains `keep-old` and its OOM protections. NAS has distributed Nix
  builds enabled, `max-jobs = 0`, and two `ssh-ng` builders, each with two
  build slots. `fleet-exec` provides explicit heavy-command dispatch with
  strict host-key checking and no local fallback. Its quoting/failure tests
  use fixtures; no real builder job or command was dispatched in this pass.
- **Inference:** NAS's utility endpoint is `http://strix-coordinator:8731`,
  model `qwen3.8-flash-next`; no model server is placed on NAS. Both compute
  hosts boot their single-box Gufo service. TP2 is declared on both, but has
  no boot target and conflicts with those single-box units.
- **Donnerkeule:** both compute hosts realize the same module from
  `a36a6cc2b8a36e59e0ada17578b52d57849bdf07`, built for the selected kernel.
  The matching `rdma-core-usb4` provider and Gufo RDMA
  `39f437cc1316c2b24031fef983462feaac88b9d5` also build. Read-only `modinfo`
  reports `7.3.0 SMP preempt mod_unload`. Gufo's direct store references
  contain the custom USB4 provider. Available store/cache outputs were reused;
  this is successful realization, not a claim of recompiling every dependency.
- **Latency hold:** the TP2 companion has a 100 microsecond budget and is
  required by TP2. The policy check exercises the held descriptor against a
  temporary file. No live `/dev/cpu_dma_latency` experiment was performed.
- **First-boot helpers:** worker and client carry raw helpers in the Nix
  store. Coordinator and NAS still require the reviewed raw checkout at
  `/home/tom/mecattaf/dotfiles`.

The full `nix flake check --keep-going` succeeds for all 52 checks, including building checks,
not just evaluating them. Both production deploy checks succeed too. The
JSON companion lists the exact checked outputs and exit codes.

All tests/builds ran through `runtime-test`. A five-second disk-space guard
would interrupt only this task's build process group below 25 GiB free.
Minimum observed free space was 164.6 GiB; receipts record the exact values. No live runtime directory
cleanup or service repair was used to make checks pass.

## Conflicts and fixes for the owners

| PR | Required integration work |
| --- | --- |
| #575 | Clean merge. Its two seat rule links must survive #608's move to `home/agent-tools.nix`. |
| #611 | Clean merge. Latest #608/#610 already agree on `linuxPackages_7_3`. Keep this kernel selection and fresh-input pin when rebasing; do not reintroduce #583. |
| #605 | Clean merge after #611. Its newer complete Gufo retirement must survive the older retirement embedded in later branches. |
| #604 | Resolve `AGENTS.md`, `modules/fleet-status.nix` and `modules/strix.nix` by combining Gufo provider semantics with role gates; never restore the removed Halogen declarations. Merge `9420130f`. |
| #608 | Rebase the host rename and moved agent configuration against the actual #605 retirement. Combine Gufo labels/settings with renamed endpoints in local-AI monthly and vendored Substrate code/tests. Remove old `hosts/strix/default.nix`, retain the new tailnet profiles and worker in-store helpers, and move #575's rule links to agent-tools. Merge `c72b5835`. Its new comment containing `bootctl` exposed an existing scanner false positive; `b1fef43` bounds the retired tool-name match rather than matching a valid command prefix. |
| #607 | Combine the NAS agent split with agent-tools/agent-helpers without duplicate package allowlists. Resolve `REKEY.md`, `secrets.nix`, role checks, client descriptions and shared transport comments. Checks must use real renamed hosts, NAS package versions and the TP2-only compute credential exception. Remove the obsolete PARTUUID diagnostic shim and rebase the transport guide on #606/#608's final disk/helper declarations. Merge `bd3d11d1`; repairs `70e43096` and `6d2c1253`. |
| #606 | Retain all check registrations when resolving `flake.nix`. Use its production serial-bearing by-id mount, remove all old integration PARTUUID overrides, and retain serial/mount validation and `--bench` pre-fill. Merge `574f3f7c`. No remaining production evaluation guard needs a UUID filled in. |
| #609 | Resolve its add/add endpoint to canonical `strix-coordinator`. Preserve the moved, role-gated agent settings rather than restoring them unconditionally in `home/home.nix`. dsh stays on NAS. Merge `ebfe7050`. |
| #610 | Preserve #608/#607's enabled worker Tailscale assertions; its older topology test still asserted the opposite. Combine NAS recipient rules with the TP2-only token, and retain the 7.3/a36a6cc2 pin and 100 us hold. Combine dsh watch rows with renamed attributes, target agent/Herdr update gates at NAS, and watch the worker kernel. Merge `87165e6e`. Resolve the USB4 mode and TP2 boot-readiness gaps below before claiming the full requested first boot. |

Use `git show --remerge-diff <merge>` for exact conflict resolutions. The
post-merge commits are deliberately separate from the workers' branch heads.
The NAS metadata CLI remains stable's 1.10.2; its authenticated metadata and
cache-integrity smoke contract passes unchanged.

## Exactly what remains before the unplug instruction

1. **Settle the fast-link configuration.** Current #610 selects four RDMA
   rails, blacklists `thunderbolt_net` and `thunderbolt_stream`, and gives
   each cable/controller's two payload ring pairs to Donnerkeule. It does
   not restore the old USB4 IP/stream links alongside that mode. Ethernet
   management plus two RDMA cables is declared; concurrent legacy USB4
   networking is not. Existing decision D-44 tracks this conflict. Select
   and qualify a supported arrangement; do not call the two modes equivalent.
2. **Prepare the worker's actual boot disk.** Serial `26051Y809195` is still
   an occupied disk in the coordinator, with a reportedly blank ESP. #608's
   measured UUIDs and preserving-install guide replace the earlier fresh-wipe
   assumptions. Writes to this disk and formatting its confirmed blank ESP
   still require the attended authorization/backup step. Archive old home,
   credentials and retired identities, install the final worker closure,
   verify its boot files and stage its model loans before moving it.
   Falling back to an installer after the move does not meet first-power-on
   into the new role. See `docs/strix-worker-install.md` and existing D-43.
3. **Prepare and pre-fill NAS home on the bench.** Verify serial
   `260538801482`, preserve wanted Windows data, partition/format it as
   #606 specifies, and create `@home`/`@snapshots`. Use the reviewed helper's
   `--bench` mode for the curated copy. Preserve NAS's legacy home separately.
   Complete the sealed source/NAS escrow, consistent Claude/Codex DB and
   rollout capture, final delta and checksum no-difference pass. There is no
   PARTUUID edit to perform. Flush and unmount before the shared power-off.
4. **Finish credentials and trust, then rebuild affected outputs.** The
   worker public host key is still empty. Obtain its fresh key through a
   trusted path, commit its public half, and install its private half only
   on its final root. Tom's 18-file NAS rekey is unperformed here. Create
   the TP2-only shared token after both compute keys are recorded; its
   ciphertext is currently absent. Preserve NAS and coordinator identities;
   do not clone one node's SSH or Tailscale identity to another.
5. **Complete four-node enrollment and non-expiry proof.** A read-only live
   observation in this pass sees `strix`, `nas`, and `client`; neither new
   canonical Strix identity is present. The new transport checker fails on
   those missing identities, the local name and missing active NAS exit
   selection. NAS exit/subnet approval is visible. Existing nodes report no
   key expiry, which is not an independent admin-console proof. Enroll/name
   the final worker/coordinator identities, preserve their state on the final
   roots, set/record **Key expiry disabled** for all four, and verify the
   required exit, subnet and HTTPS approvals. Pre-enrollment is prepared but
   not performed; a first-boot login is an outstanding hands-on step.
6. **Stage the final boot generations and boot-required data.** Only built
   closures exist from this pass. Stage coordinator and NAS without activating
   the new roles on the live system, complete the offline worker install,
   and update the client through its authorized deploy path. Stage the raw
   checkout on NAS/coordinator and verified Library model loans on both
   compute roots. Retain recovery boot entries and direct LAN/console access.
   Complete firmware, disk, NIC/MAC and cable/port identity checks.
7. **Make the promised TP2 startup behavior concrete.** Current boot enables
   independent single-box Gufo on both machines, using the pinned upstream
   package; the RDMA fork is only the on-demand TP2 package. TP2 has no boot
   target and its token is absent. Automatic dual-host inference after the
   coordinated power cycle is therefore not implemented/qualified. Resolve
   its startup policy and rail/token/model prerequisites before promising it.

Power-off ends live PTYs. Save recoverable session state and original working
directories deliberately; a file copy does not preserve running processes.
The earlier coordinator-first intermediate brain boot is superseded and must
not be used as the plan for this pass.

## Acceptance after the physical move

Boot and verify each final host on 7.3. Check NAS's actual home mount, UID and
recoverable harness sessions; four distinct online tailnet identities and
admin expiry receipts; client access to NAS Herdr; LAN and roaming exit/subnet
traffic; successful Nix jobs on **both** remote builders with no NAS local
compilation; and real `fleet-exec` command success/failure propagation.

On the Strix pair, verify both cables train correctly, all intended verbs
ports/rails become active, per-cable and combined throughput works both ways,
the 100 us latency hold's lifecycle is correct, and Gufo single-box/TP2
correctness and readiness meet the chosen boot policy. These are supervised
hardware checks, not facts established by this build. The code-level role,
transport and latency tests do not substitute for them.

Raw logs and receipts: `~/friday-oct23/dual-strix-migration/integration-proof-linux73/`.
The `verified-*` files identify the final tested source. The full live
Tailscale status is kept privately outside Git; only a narrow observation
summary is published in the JSON evidence.
