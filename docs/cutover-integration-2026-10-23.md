# October 23 cutover: combined build proof

The combined stack evaluates and builds on **Linux 7.2.12** for
strix-coordinator, strix-worker and client. The NAS also evaluates and builds
with an explicitly invented test PARTUUID. Its production configuration still
refuses to build until the real home partition exists and its verified
PARTUUID is recorded. **Never activate the NAS test output.**

This is an inspection branch, **not a PR or a branch to merge**. No production
PR, main branch, live checkout, service, module or boot configuration was
changed. No ciphertext was printed, decrypted or rewritten. No model weights
were fetched or moved.

## Exact source

- Base: `7a794a5ea955f3c20dac70f5a8b0f6425f929427` (`origin/main`).
- Tested code: `9c98b60` on `integration/cutover-2026-10-23`.
- The later evidence commit adds only this report and JSON receipts.
- Branch heads below were fetched and checked again against the remote;
  none advanced during integration.

| Order | PR | Branch | Tested head |
| --- | --- | --- | --- |
| 1 | #575 | `rules/ultracode-light-verify` | `f501e856` |
| 2 | #583 | `update/nixpkgs-fresh` | `72bec454` |
| 3 | #605 | `gufo/retire-halogen-oct23` | `af8f4811` |
| 4 | #604 | `fleet/roles` | `4b260c69` |
| 5a | #608 | `fleet/strix-coordinator-worker` | `ad94870c` |
| 5b | #607 | `nas/agent-host` | `3c608be3` |
| 5c | #606 | `nas/home-disk` | `a8d5bdf4` |
| 6 | #609 | `dsh/nas-placement` | `15e0c550` |
| 7 | #610 | `compute/donnerkeule-gufo-rdma` | `51a37cc0` |

Each branch was merged locally, in this order, with a separate integration
merge commit. Conflict resolutions are inspectable with
`git show --remerge-diff <merge-commit>`; subsequent integration commits contain
the evaluation/check repairs. The workers' branches were not changed.

## Host results

| Host | Toplevel evaluates | Full toplevel builds | Kernel |
| --- | --- | --- | --- |
| strix-coordinator | Yes | Yes | 7.2.12 |
| strix-worker | Yes | Yes | 7.2.12 |
| nas, production | Refused by the intended PARTUUID assertion | Blocked by that assertion | Selects 7.2.12 |
| nas, test UUID only | Yes | Yes | 7.2.12 |
| client | Yes | Yes | 7.2.12 |

All four select the **same kernel derivation**, not merely equal version text:
`/nix/store/8zfh2xmv3yvsz655bp1jrq5laaqv0fk4-linux-7.2.12.drv`.
The NAS retains stable userspace; this does not freeze its kernel.

`tests/cutover-integration/default.nix` asserts the shared kernel derivation and
the identical Donnerkeule derivation on both compute hosts. It extends only
the NAS PARTUUID with `11111111-2222-4333-8444-555555555555`. It does not change
the production guard or introduce a deploy target.

The machine-readable companion, `cutover-integration-2026-10-23.json`, records
the exact output paths, derivations, commands, checks and exit codes.

## Donnerkeule and Gufo RDMA

The combined build successfully realizes all three packages:

- Donnerkeule: `fb05a7d210179fa2daaefe3e7bf45bbb4a0b7ff3`.
- USB4 provider: `rdma-core-usb4-63.0`, from that Donnerkeule source.
- Gufo RDMA: `39f437cc1316c2b24031fef983462feaac88b9d5`.

The module is actually installed under `lib/modules/7.2.12/extra/` and its
read-only `modinfo -F vermagic` result is `7.2.12 SMP preempt mod_unload`.
Gufo RDMA's direct store references include the custom rdma-core output, which
contains `libibverbs/libusb4_rdma-rdmav59.so`. The two compute hosts use this
same module/provider pair. Nix reused available store outputs and cached
dependencies; this does not claim a fresh compilation of every dependency.

The resident single-box Gufo remains pinned at
`0c03748a271eab895befc0d2343aa50ca4b6d836`. The RDMA fork is the on-demand TP2
package; its service has no boot target. No driver was loaded and no inference,
USB4 link, throughput or model-correctness test ran on the live system.

## Fixes to carry back to the PRs

| PR | Conflicts and required changes before landing in the requested order |
| --- | --- |
| #575 | Merges cleanly. Preserve both seat rule links when #608 moves agent configuration into `home/agent-tools.nix`. No independent change needed here. |
| #583 | Lock-only merge is clean and produces 7.2.12 on all four hosts, including the restored worker. No kernel or Donnerkeule patch is needed. |
| #605 | Merges cleanly after #583. Later branches must preserve this newer retirement, including Gufo provider/runtime labels, served model IDs and bounded model settings. Their embedded older retirement is not an equivalent replacement. |
| #604 | Resolve `AGENTS.md`, `modules/fleet-status.nix` and `modules/strix.nix` against #605: retain complete retirement, use Gufo for inference facts, preserve the brain-role attention gate, and do not restore Halogen declarations. Integration merge: `11d76ce7`. |
| #608 | Rebase onto the actual #605 retirement. Resolve the removed `hosts/strix/default.nix` by keeping the new coordinator/worker layout. Combine Gufo provider/settings with canonical host names and endpoint injection in local-AI monthly and vendored Substrate source/tests. Keep agent settings in `home/agent-tools.nix`, move #575's two links there, and remove the old unconditional block in `home/home.nix`. Update the Substrate fixture's leftover Halogen seat and timeout key to Gufo. Integration merge: `c0dba325`. |
| #607 | Resolve `REKEY.md`, `secrets.nix`, `home/home.nix`, `home/harness-records.nix`, and `tests/fleet-roles/default.nix` while preserving #608's clean compute hosts. Retain both agent-tools and agent-helpers imports without restoring a duplicate package allowlist. Test real renamed configurations; compare NAS and fleet kernel versions instead of asserting 7.2.10. Permit only the TP2-specific credential exception in compute recipient tests. Retarget the metadata CLI smoke to the NAS's actual wrapper/version, 1.10.2; its full authenticated metadata/cache contract passes unchanged. Remove old NAS frozen-kernel comments. Integration merge: `aa2b3b70`, plus the subsequent check repairs. |
| #606 | Resolve the `flake.nix` check-registration conflict by retaining all three of `nas-agent-host`, `fleet-roles` and `nas-home-disk`. Keep the PARTUUID refusal. Filling it requires the real partition, not an integration test UUID. Integration merge: `a8c784a8`. |
| #609 | Resolve the add/add in `lib/local-model.nix` to the canonical `http://strix-coordinator:8731`. Its `home/home.nix` conflict must preserve the moved agent-settings block, adding dsh-specific configuration in its own module. Keep dsh on the NAS and its checks/key path there. Integration merge: `ac06b75f`. |
| #610 | Combine the TP2 credential/runbook additions with the NAS operator-recipient rules, rather than replacing them with the intermediate admin-only rules. Combine renamed watch attributes with the NAS dsh row. Move llm-agents update gates to NAS/client and the Herdr server gate to NAS; include the worker in kernel-series watches. Keep the TP2 token as the sole compute credential exception. Integration merge: `28115e7f`, plus manifest commit `9c98b60`. |

For #608, the larger conflict set also included `flake.nix`,
`modules/fleet-status.nix`, `modules/strix.nix`, the local-AI monthly registry
and workflow fixture, vendored Substrate `backend.ts`, `microvm.ts`,
`sessions.test.ts`, `successor-r4.test.ts`, and `tests/substrate-modules`.
These resolutions combine host relocation with the new provider contract;
choosing either side wholesale loses one of them.

## Verification

The final combined build command returned 0 for four full host toplevels plus
Donnerkeule, the USB4 provider and Gufo RDMA. These 14 checks also built with
exit 0:

`nas-agent-host`, `nas-home-disk`, `fleet-roles`, `closet-topology`, `gufo-rdma`,
`substrate-modules`, `dsh-config`, `dsh-plugins`, `gufo-unit-policy`,
`utility-model`, `local-model-transactions`, `huggingface-cli-smoke`, `seats`,
and `update-check`.

The complete `nix flake check --no-build --keep-going` returned **1 as
expected**: the production NAS toplevel and its `deploy-schema` and
`deploy-activate` checks encounter the PARTUUID guard. All other 49 check
derivations evaluated. This is not a claim that the unmodified production
flake is fully green, or that every check was built.

Builds and shell-bearing checks ran through `runtime-test`. The disk guard
polled free space every five seconds and would interrupt only this task's
build process group below 25 GiB. No run reached that threshold. Root started
with 166 GiB available and minimum observed free space was 161.9 GiB. No
garbage collection, service repair or live runtime cleanup was performed.

Raw logs and preliminary/final receipts remain on this Strix at
`~/friday-oct23/dual-strix-migration/integration-proof/`. The `verified-*`
receipts identify the final tested code, rather than the preliminary runs.

To reproduce from the tested code, check disk space first, then:

```sh
~/.local/bin/runtime-test -- nix build --json --no-link --keep-going \
  --max-jobs 1 --cores 4 --impure --expr '
    let
      f = builtins.getFlake (toString ./.);
      p = import ./tests/cutover-integration { flake = f; };
    in builtins.attrValues p.hosts ++ [
      f.packages.x86_64-linux.thunderbolt-ibverbs
      f.packages.x86_64-linux.rdmaCoreUsb4
      f.packages.x86_64-linux.gufo-rdma
    ]'
```

This command builds a fictitious NAS filesystem configuration. Its output
must never be selected for installation, boot or activation.

## What still gates tonight

1. **Production NAS:** record the verified incoming SSD p2 PARTUUID after the
   real disk/serial checks, then build the production NAS toplevel again.
   The fixture does not qualify that partition or its data.
2. **Credentials:** Tom must perform the 18-file NAS rekey described in
   `REKEY.md`. Existing ciphertext still has the former recipients; a build
   does not prove NAS decryption. Neither this integration nor its tests
   perform that transaction.
3. **Worker installation:** record its fresh SSH host public key and verify
   disk, MAC, PCI identities and firmware on the actual returned machine.
   The empty registry key is intentionally not fabricated by this check.
4. **Order and continuity:** the supplied runbook still says 7.2.10 and puts
   the fresh-input bump later. Reconcile it with the requested 7.2.12 plan and
   coordinator-first physical order. Do not boot the coordinator into its
   compute-only role while it is still the only agent/session host. #607's
   `REKEY.md` says to keep its brain generation for the first boot and use a
   later plain reboot after NAS handover. Prove NAS-local session continuity
   and the preserved home/databases before retiring the old brain.
5. **TP2, separately from the base cutover:** create the shared TP2 service
   token after the fresh worker host key exists. The token ciphertext is
   absent, so the TP2 unit cannot start yet. Then qualify the actual four
   20 Gb/s rails, verbs ports, bidirectional throughput and Gufo correctness.
   Successful package builds do not discharge these hardware gates.

There is no remaining combined-stack evaluation/build failure beyond the
intentional production NAS PARTUUID refusal. The Strix remains on its live
7.2.10 kernel throughout this work; all 7.2.12 results above are built outputs.
