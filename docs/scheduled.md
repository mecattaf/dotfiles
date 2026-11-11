# Scheduled

Scheduled is Tom's work that happens later, on a cron time, without a
systemd timer per job. The dotfiles declare exactly one clock for it: the
`scheduled-heartbeat.service`/`.timer` pair (D52, hourly, OnStartupSec
2min, Persistent, `home/scheduled.nix`, NAS only). The heartbeat holds no
schedule of its own. Each hourly tick reads the JSONC workflow files at
`<agency>/.agency/workflows/<stem>.jsonc` — one workflow, one file; the
master agency is `~` — decodes their cron times against the present hour,
writes due work to the spool, and wakes the factory floor: the `floor`
dshd instance, the superagent fork in the dsh config, which runs the
work. dshd itself stays free of clocks ("NO SCHEDULES EVER"), and
Substrate does not decide what is due. Everything else scheduled is a
workflow file; the runbook below is for the machine Tom sits at (the NAS)
and the `scheduled` CLI, the one program every reader and writer of a
workflow goes through.

## Commissioning order

The order matters; each step assumes the previous one landed. Rollback at
any step is the previous NixOS generation, which removes the units and
the program and leaves `~/.agency` as it was.

1. Branch, gates, merge: `nix eval` on the NAS; the VM checks on
   strix-coordinator after `df -h /`; the NAS toplevel build;
   `switch-to-configuration dry-activate` on the NAS.
2. Merge, then switch the NAS, attended. This switch rewrites
   `/etc/dshd/releases/nas`, so it is never the nightly one. After it the
   timer runs; every tick is skipped by `ConditionPathIsDirectory` until
   `~/.agency` exists.
3. Install the floor plugin through the dsh plugin manager and create the
   `floor` instance. That creates `~/.agency/state/master`.
4. Place the master workflow files, with `fleet-nightly` disabled.
5. First tick by hand, then read the journal:

   ```sh
   systemctl --user start scheduled-heartbeat.service
   journalctl --user -u scheduled-heartbeat -n 20 -o cat
   ```

   Expect a `pass` line, no `<3>` line, and `heartbeat.json` written.
6. Rebase #642 (`fleet-update`), pass its gates, merge, switch attended.
7. Tom arms `fleet-nightly` — only Tom.
8. The morning after the first armed night: read the night's receipt and
   the occurrence's history.

## Everyday commands

Run these as Tom's user on the NAS. `ID` is `<agency id>:<stem>`; a bare
stem resolves when exactly one agency has it.

```sh
scheduled ls                 # header from the timer, one row per workflow
scheduled show ID            # the live file plus recent occurrences
scheduled validate --all     # or explicit PATHs, or --stdin --as PATH
scheduled new ID --cron '0 6 * * *' --tz Europe/Paris --prompt TEXT [--paused]
scheduled put ID --expect none --by cc < file.jsonc   # new; REV to replace
scheduled set ID enabled false          # pause (true to arm)
scheduled rm ID --expect REV --by cc
scheduled run ID [--input k=v] [--wait]  # manual occurrence; gates still apply
scheduled history ID -n 20
scheduled history ID --occurrence KEY --log
```

Writes validate first and refuse invalid text; `--expect` compares with
the current revision (`none` = must not exist). A conflict exits 3 and
nothing is written. `run` splices into the same path as a scheduled fire:
it validates the live file (paused is allowed), writes the manual spool
file, and starts the heartbeat once if the floor is not running. There is
no force flag. Edits take effect at the next hourly pass, never sooner.

Proposals: an agent's unasked idea goes to `put ID --proposal`, which
writes into `proposed/` with `enabled: false` and requires an
`x-proposal {by, at, why}` block. `scheduled accept ID` moves it up and
arms it; `scheduled dismiss ID` deletes it and refuses the same stem for
30 days. Agents arm nothing Tom did not ask for.

## Journal queries

```sh
journalctl --user -u scheduled-heartbeat.service
journalctl --user -u scheduled-heartbeat -n 20 -o cat
journalctl --user -u dshd@floor.service | grep 'floor:'
```

Lines carry an sd-daemon priority prefix that journald strips into
`PRIORITY`; vocabulary `pass`, `decode`, `invalid`, `floor`, `guard`,
`update`. `reason=timer` when systemd fired it, `reason=manual`
otherwise. A typical healthy tick:

```
<6>pass reason=timer took_ms=412 discover_ms=48 agencies=1 workflows=4
```

## Failure table

| Symptom | What it means | What to do |
|---|---|---|
| `<4>invalid workflow=... rev=... at=...` | A workflow file fails validation; it is skipped, listed first by `ls` | Fix the file (`scheduled put` refuses invalid text); `scheduled validate --all` |
| `<4>floor masked` | The floor unit is masked; the tick will not start it | Unmask deliberately, or accept that the floor is off |
| `<3>floor ... state=failed ...` | The floor crashed; the tick ran `dshd start` and exits 1 anyway so the crash is seen | Read `journalctl --user -u dshd@floor.service`, fix, check the next tick |
| `<3>floor error=not-found` | No `floor` instance exists | Create it (commissioning step 3) |
| `<3>floor` with a dshd `remedy` | Instance `orphaned`, `inconsistent` or `unknown` | Follow dshd's remedy; `dshd get --json floor` to inspect |
| `<3>guard machine-id differs: state from another host` | `~/.agency/state` came from a different machine | Restore the local state; never share it between hosts |
| `<4>floor action=none ... waiting=N` | The floor is stopped by intent while work waits | Intended until Tom arms the floor; work stays queued |
| exit 4 from any verb | State dir or floor DB unreadable | Check `~/.agency/state/master` permissions and existence |
| exit 3 from a write verb | `--expect` revision conflict | `scheduled show ID`, re-apply against the current revision |
| exit 1 from a verb | Refused: invalid, not found, proposal limit | Read the message; `scheduled validate` the text |
| exit 2 from a verb | Usage error | `scheduled schema`, retype |

The user-unit tripwire sees the heartbeat's exit 1 as a failed start job,
so a refused tick surfaces; the tick never runs `reset-failed`. When the
floor is `running` and the release is `outdated` with no Eval in
progress, the tick issues the one `dshd update -R --json floor` verb;
runs are separate units and are not touched.

## Rollback

Any step back is the previous NixOS generation: it removes the units and
the program and leaves `~/.agency` untouched. To quiet things without a
generation switch: disable the timer through Home Manager and stop the
floor with `dshd stop floor`. Workflow files are plain files under
`~/.agency/workflows/`; pausing individual work is `scheduled set ID
enabled false`.

## State at install (11 Nov 2026)

Every baseline workflow ships with `"enabled": false`, and the floor is
stopped by intent until Tom arms them: the heartbeat ticks, finds nothing
armed, and passes. Nothing runs unattended before Tom arms
`fleet-nightly` (commissioning step 7) and opens the floor. Expect
`<4>floor action=none` lines while the floor stays deliberately down —
that is the configured state, not a failure.
