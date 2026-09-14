# Runbook conventions: suppressing a unit on NixOS

Written 2026-09-13 for #263, corrected 2026-09-14 after measuring
`mask --runtime`. A runbook is prose an operator (or an agent) will paste into
a root shell, so a wrong verb in one is a wrong command on a live host. This
page is where the verb for "make this unit not run" is decided.

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
system`.

**`systemctl mask --runtime` is worse: it succeeds and does nothing.** It
writes the `/dev/null` link under `/run/systemd/system`, but systemd reads
unit directories in priority order and `/etc/systemd/system` comes BEFORE
`/run/systemd/system` (`systemd-analyze unit-paths`). On a conventional
distro the unit file lives in `/usr/lib`, below `/run`, so the runtime mask
shadows it; on NixOS the unit file itself lives in `/etc/systemd/system`, so
the store copy shadows the mask. MEASURED 2026-09-14 on the coordinator with
a throwaway user unit placed in `~/.config/systemd/user` (the user manager's
analogue of `/etc/systemd/system`, likewise ahead of
`$XDG_RUNTIME_DIR/systemd/user`): `systemctl --user mask --runtime` printed
`Created symlink … → /dev/null` and exited 0, `LoadState` stayed `loaded`,
and `systemctl --user start` ran the unit anyway.

Drop-ins are different: systemd merges `<unit>.d/*.conf` from EVERY unit
directory regardless of priority, so a drop-in under `/run` does apply to a
unit whose file is in the store. Same measurement: a
`/run/user/1000/systemd/user/<unit>.d/50-off.conf` carrying
`ConditionPathExists=/nonexistent` made `start` skip the unit
(`ConditionResult=no`). `/run` is a tmpfs, so it is gone at the next boot.

## Intent → wrong → right

| Intent | Wrong | Right |
|---|---|---|
| Keep a unit from starting **for this boot only** | `systemctl mask <unit>` (fails: read-only store symlink); `systemctl mask --runtime <unit>` (exits 0, masks nothing) | `systemctl stop <unit>`, then a runtime drop-in: `mkdir -p /run/systemd/system/<unit>.d && printf '[Unit]\nConditionPathExists=/nonexistent\n' > /run/systemd/system/<unit>.d/50-off.conf && systemctl daemon-reload` (or `systemctl edit --runtime <unit>` and type the same two lines). Check with `systemctl show -p DropInPaths <unit>`. Dies at reboot, which is the point; `rm` the file and `daemon-reload` to undo sooner. A drop-in on a `.timer` stops the timer from firing the same way |
| Keep a unit from starting **durably** | `systemctl mask <unit>`, or `systemctl disable <unit>` (both write to the store tree, and the next switch undoes a hand edit anyway) | `systemd.services.<unit>.enable = false;` in the host's Nix file, then a rebuild. The host's Nix file is what decides, so the runbook names it |
| **Protect data** a unit would touch (prune, sync, delete) | Masking the unit and hoping nothing re-enables it | Move the data out of the unit's scope (another path, another dataset, a read-only snapshot), so the unit running is harmless |
| Quiet a **timer during maintenance** | `systemctl mask <timer>` | `systemctl stop <timer>` and accept that the next switch restarts it — or leave it running if its run is harmless. If a switch may land inside the window, add the runtime drop-in from the first row |

## The rule

A runbook that suppresses a unit **across a reboot** uses the durable form:
`systemd.services.<unit>.enable = false;` (or `systemd.timers.<unit>.enable`)
plus a rebuild, in a reviewed commit. A runtime drop-in is only ever for
"until the next boot", and the runbook says so in those words. No runbook in
this fleet says `mask`, with or without `--runtime`.

## History

The mistake this page exists to stop was drafted twice, in issue prose and
session handoffs, and never reached the tree (`git grep 'systemctl mask'` had
no hits when #263 was audited):

- 2026-08, the flashnext-fp8 prune mitigation drafted
  `systemctl mask local-models-sync.service` to keep the sync from pruning
  weights mid-experiment.
- The same shape was drafted for `tb-link-heal.timer` on the Thunderbolt rail.

#263 itself proposed `mask --runtime` as the one-boot form; the 2026-09-14
measurement above is why this page does not. Neither example unit exists any
more: `systemctl list-unit-files 'tb-*' 'local-models*'` lists 0 unit files on
the coordinator and the worker (2026-09-13). The fleet serves one model, on
Halogen (AGENTS.md), and the Thunderbolt rail and its residue are gone by
Tom's 2026-09-11 ruling (DECISIONS.md, "2026-09-11, later the same day: the
Thunderbolt residue goes too"). The examples are history; the table above is
not.
