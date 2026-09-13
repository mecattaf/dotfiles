# Runbook conventions: suppressing a unit on NixOS

Written 2026-09-13 for #263. A runbook is prose an operator (or an agent) will
paste into a root shell, so a wrong verb in one is a wrong command on a live
host. This page is where the verb for "make this unit not run" is decided.

## Why `systemctl mask` does not work here

`systemctl mask <unit>` writes a `/dev/null` symlink into
`/etc/systemd/system`. On every host of this fleet that directory is not a
directory Nix lets you write:

```
/etc/systemd/system -> /etc/static/systemd/system -> /nix/store/…-system-units
```

(`readlink -f /etc/systemd/system` on the coordinator and the worker, both
resolving into a read-only `/nix/store/…-system-units`, re-checked
2026-09-13.) Plain `systemctl mask` therefore fails with `Read-only file
system`. `systemctl mask --runtime` does work, because it writes under
`/run/systemd` instead — and `/run` is a tmpfs, so the mask is gone at the next
boot. Anything that must survive a reboot has to be said in Nix.

## Intent → wrong → right

| Intent | Wrong | Right |
|---|---|---|
| Keep a unit from starting **for this boot only** | `systemctl mask <unit>` (fails: read-only store symlink) | `systemctl mask --runtime <unit>` — dies at reboot, which is the point |
| Keep a unit from starting **durably** | `systemctl mask <unit>`, or `systemctl disable <unit>` (both write to the store tree, and the next switch undoes a hand edit anyway) | `systemd.services.<unit>.enable = false;` in the host's Nix file, then a rebuild. The host's Nix file is what decides, so the runbook names it |
| **Protect data** a unit would touch (prune, sync, delete) | Masking the unit and hoping nothing re-enables it | Move the data out of the unit's scope (another path, another dataset, a read-only snapshot), so the unit running is harmless |
| Quiet a **timer during maintenance** | `systemctl mask <timer>` | `systemctl stop <timer>` and accept that the next switch restarts it — or leave it running if its run is harmless |

## The rule

A runbook that suppresses a unit **across a reboot** uses the durable form:
`systemd.services.<unit>.enable = false;` (or `systemd.timers.<unit>.enable`)
plus a rebuild, in a reviewed commit. `mask --runtime` is only ever for "until
the next boot", and the runbook says so in those words.

## History

The mistake this page exists to stop was drafted twice, in issue prose and
session handoffs, and never reached the tree (`git grep 'systemctl mask'` had
no hits when #263 was audited):

- 2026-08, the flashnext-fp8 prune mitigation drafted
  `systemctl mask local-models-sync.service` to keep the sync from pruning
  weights mid-experiment.
- The same shape was drafted for `tb-link-heal.timer` on the Thunderbolt rail.

Neither unit exists any more: `systemctl list-unit-files 'tb-*'
'local-models*'` lists 0 unit files on the coordinator and the worker
(2026-09-13). The fleet serves one model, on Halogen (AGENTS.md), and the
Thunderbolt rail and its residue are gone by Tom's 2026-09-11 ruling
(DECISIONS.md, "2026-09-11, later the same day: the Thunderbolt residue goes
too"). The examples are history; the table above is not.
