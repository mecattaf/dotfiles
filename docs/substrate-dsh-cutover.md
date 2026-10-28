# NAS scheduler execution through DSH

The Cloudflare Floor remains the only nightly clock. NAS owns the capacity
pusher, interpreter, DSH processes, credentials and histories. Strix coordinator
owns inference and explicit build/test execution. The dormant worker receives no
work. The local runtime is DSH with provider `gufo`, model
`qwen3.8-flash-next`, and capacity seat `gufo`.

The module renders one local DSH execution slot and a 1 GiB soft / 2 GiB hard
memory budget. Its user profile supplies the harnesses; no Pi package or Pi
provider is needed. Changed puller configuration does not restart an existing
run. Tokens remain agenix credentials on NAS and do not enter Nix store files
or remote compute checkouts.

## Explicit commissioning

A fresh seed catalog supports DSH. Existing catalogs remain private runtime
data and are never overwritten by Nix activation. Use the migration command
first in its default read-only mode:

```sh
substrate-dsh-catalog
substrate-dsh-catalog --apply
```

The apply operation holds a separate lock, creates a mode-0600 exact backup,
converts the existing local Flash-Next row to DSH/Gufo and removes legacy
Pi-specific metadata and retired provider rows from the active catalog. Their
full original data remains in the backup. It preserves other supported model
choices, adds `local` and `nightly` aliases, and refuses unknown local models,
alias conflicts, alternate defaults and symlinks. A second apply changes
nothing. The executor refuses a stale Pi catalog rather than silently routing
through a removed harness.

Before starting the restored holder, inspect the Floor's current sessions,
queued messages and jobs. Keep the existing `coordinator` holder paused during
this audit. The old Pi routine is historical evidence: create a supported DSH
session and replace its routine binding with at most one enabled nightly
trigger. Changing only its model does not migrate its harness. Do not replay
unrelated queued work as a side effect of restoring execution.

After reviewing the generation's activation effects and preserving the active
Herdr/user-manager/transport identities, start only the new scheduler units.
Do not restart Herdr, the user manager, networking or an ongoing interpreter
run. Commission the actual DSH first-turn/resume and project-MCP paths before
unpausing the audited work. Observe final nightly job results separately from
a successful model turn or detached launch.

## Validation boundaries

`checks.x86_64-linux.substrate-modules` parses rendered unit, runtime, model
catalog and credential-placeholder data; its eight file migration tests cover
backup, idempotence and refusal behavior. `fleet-roles` ensures compute hosts
receive no agent service or credential wiring. Execute these derivations on
strix-coordinator, checking `df -h /` and at least 25 GiB free before every
`nix build`. Runtime-sensitive tests use `runtime-test` on their execution host.

These checks prove implementation contracts. They do not prove the NAS has
activated this configuration, its holder is serving, or the nightly update has
completed. Record those live observations and exact revisions after rollout.
