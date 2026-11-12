# Scheduled

Scheduled is Tom's work that happens later, on a cron time, without a
systemd timer per job. The dotfiles declare exactly one clock for it: the
`scheduled-heartbeat.service`/`.timer` pair (D52, hourly, OnStartupSec
2min, Persistent, `home/scheduled.nix`, NAS only).

The heartbeat is a nudger. Each tick:
- reads the item files at `<agency>/.agency/scheduled/<item>.jsonc` (one
  item per file; the master agency is `~`);
- decodes their cron times against the present hour;
- links one occurrence record per due item into the superagent's inbox;
- starts the `floor` dshd instance when records wait.

It holds no superagent logic. The floor's scheduled Source turns each
record into a Trigger, and the main Session reads the item's text and
decides what, if anything, to do. The heartbeat never:
- runs `dshd run` or `dshd update`;
- calls the floor's HTTP API;
- opens `orchestrator.sqlite`;
- runs a command from an item.

dshd itself stays free of clocks ("NO SCHEDULES EVER").

## The pieces

| What | Where |
|---|---|
| Items | `<agency>/.agency/scheduled/<item>.jsonc`, schema v1 (`scheduled schema`) |
| Inbox, written by the heartbeat and by `scheduled run` | `<stateDir>/inbox/scheduled/*.json`, through `.tmp/` |
| Inbox, owned by the floor's Source | `.done/` (received), `.bad/` (refused, with `<name>.error`) |
| Heartbeat state (`heartbeat.json`, `intake.json`, `.tick.lock`) | `~/.local/state/scheduled` (systemd `StateDirectory`) |
| The floor | dshd instance `floor` (`SCHEDULED_FLOOR_INSTANCE`) |

`<stateDir>` is the Master profile's dsh-superagent `stateDir`
(`programs.dsh.master.stateDir`, default `~/.agency/state/master`), and it
is the one value the two sides share. `home/scheduled.nix` passes
`SCHEDULED_INBOX=<stateDir>/inbox/scheduled` to the service and to login
shells. `tests/scheduled` asserts that the two agree.

The floor's DSH profiles, `master` and one `master-<pair>` per worker
pair, are rendered from one source; see [dsh-master.md](dsh-master.md).

## An item

```jsonc
{
  "$schema": "scheduled-item.v1",
  "name": "Journal day",                      // optional; defaults to the file stem
  "enabled": false,                           // required: false writes no record
  "on": { "schedule": [{ "cron": "0 6 * * *", "timezone": "Europe/Paris" }] },
  "job": { "prompt": "Compile yesterday's journal." }   // or "prompt-file": ".agency/prompts/x.md"
}
```

Any condition, outcome check, hold or context goes into `job.prompt` in
words: the main Session judges it. Some keys are errors that name where
their intent now goes:
- `if`, `window`, `outcome`, `hold`, `context`;
- `concurrency`, `permissions`;
- `on.workflow_dispatch`;
- `job.cwd`, `job.timeout`.

`model`, `profile`, `priority`, `pair`, `env` and `secrets` are refused.

A `prompt-file` path is relative to the agency folder and must stay
inside it. The prompt is 1 B–32 KiB of UTF-8.

## A tick

1. Lock, then guard: a state written by another machine or a newer
   version is refused.
2. Intake: stat every item and re-parse what changed. A file younger
   than 2 s keeps its previous parse.
3. Decode: due instants in `(max(lastTick, armedSince), now]`. Only the
   latest is due, and `missed` counts the others. An item first seen in
   this pass has nothing due; neither does a first tick or a clock that
   went back.
4. Hand off: write `.tmp/<name>.<pid>.<hex>` (mode 0600, fsync), then
   `link()` it to the inbox. An existing record or `.done/<name>`
   answers `exists`.
5. Withdraw: while the floor is not running, starting or stopping, the
   tick unlinks its own waiting records of items that are no longer valid
   and enabled.
6. Wake, only when records wait:

   | Floor state | What the tick does | Exit |
   |---|---|---|
   | running, starting, stopping | nothing | 0 |
   | stopped (any ending), previous-boot, interrupted | `dshd start --json floor` | 0, or 1 if the start fails |
   | failed | `dshd start --json floor` | 1 |
   | masked | nothing | 0 |
   | not-found, orphaned, inconsistent, unavailable | nothing | 1 |

   The instance's `enabled` flag is not read. `enabled: false` items
   write no records, so nothing wakes the floor until Tom enables an item
   or runs one by hand.

Record names are `<namespace>~<item>@<yyyymmddThhmmZ>.json` for a
schedule and `<namespace>~<item>@run~<ULID>.json` for a manual run. A `/`
in the namespace is written `+`. The record format (v1) is the fork's;
`pkgs/scheduled/test/fixtures/occurrence-v1.json` is byte-identical to
the fork's `tests/fixtures/scheduled-occurrence-v1.json`.

## Commissioning order

The order matters; each step assumes the previous one landed. Rollback at
any step is the previous NixOS generation, which removes the units and
the program and leaves `~/.agency` as it was.

1. Branch, gates, merge:
   - `nix eval` on the NAS;
   - the `scheduled` and `scheduled-vm` checks on strix-coordinator,
     after `df -h /`;
   - the NAS toplevel build;
   - `switch-to-configuration dry-activate` on the NAS.
2. Switch the NAS, attended. After the switch the timer runs, but
   `ConditionPathIsDirectory` skips every tick until `~/.agency` exists.
3. Install the Master profile and create the `floor` instance. Its
   scheduled Source reads `<stateDir>/inbox/scheduled`.
4. Place the master items, every one with `"enabled": false`.
5. First tick by hand, then read the journal:

   ```sh
   systemctl --user start scheduled-heartbeat.service
   journalctl --user -u scheduled-heartbeat -n 20 -o cat
   ```

   Expect a `pass` line, no `<3>` line, and `heartbeat.json` written.
6. `scheduled run master:<item>` once. One record appears in the inbox,
   the floor starts if it was stopped, and the record moves to `.done/`.
   `scheduled history` lists it.
7. Tom enables an item. Only Tom does this.

## Everyday commands

Run these as Tom's user on the NAS. `ID` is `<agency id>:<item>`; a bare
item resolves when exactly one agency has it.

```sh
scheduled ls [--agency A]            # one row per item: enabled/disabled/invalid, next instant
scheduled show ID [-n N]             # the parsed item, next instants, last records from .done/ and .bad/
scheduled validate --all             # or explicit PATHs, or --stdin --as PATH
scheduled schema                     # the JSON Schema of item v1
scheduled new ID --cron '0 6 * * *' --tz Europe/Paris --prompt TEXT   # always enabled: false
scheduled set ID enabled true        # arm (false to disarm); --expect REV to guard
scheduled set ID on.schedule[0].cron '"0 6 * * 1"'
scheduled rm ID [--expect REV]
scheduled run ID [--json]            # one manual record now, then the wake table
scheduled history [ID] [-n N]        # what the Source received (done) or refused (bad)
```

Writes validate first and refuse invalid text. `--expect` compares with
the current revision. A conflict exits 3 and nothing is written. Edits
take effect at the next hourly pass, never sooner.

`run` works on a disabled item: `enabled: false` cancels only scheduled
occurrences. It does not wait for the work. The superagent's own record
(its Thread and Run) is where the work is followed.

Exit codes: 0 ok, 1 refused or a fault, 2 usage, 3 revision conflict.

## A workflow from a request: day prep

A workflow is not an item. It starts when the superagent is asked, in a
request that names the script and the agency; the main Session calls
`orchestrator_workflow_start`, and each `agent()` call of the script
becomes one Ticket (the fork's `docs/009-workflows.md`). An item can
only ask for that in words.

Day prep (Tom, 10 Nov, `start.md:72`: the "day prep" protocol, "done in
the early morning to preempt me having to manually do it") is the first
master workflow. Its files are kept in
`pkgs/scheduled/test/fixtures/master/.agency/` and placed in `~/.agency/`
by hand, like the items:

| File | Does |
|---|---|
| `workflows/day-prep.workflow.js` | Four read-only readers (yesterday's journal folder, `project overview`, the closed chats in yesterday's `raw-chat-index.jsonl`, `scheduled history` and `dshd ls`), then one writer of `~/notes/journal/YYYY/MM/DD/day-prep.md`, first line `# Assistant draft`. It writes nothing when the day folder is missing (`journal-day` owns the rollover) or the file exists. `args.date` is required |
| `scheduled/day-prep.jsonc` | The 05:00 Europe/Paris nudge that asks for the same start. `enabled: false` (H60) |

The request Tom sends the superagent, with the date filled in:

```text
Start the day-prep workflow in the master agency: call orchestrator_workflow_start with
{"script": ".agency/workflows/day-prep.workflow.js", "cwd": "/home/tom", "args": {"date": "YYYY-MM-DD"}}.
Accept its nodes as they come; it writes only that day's day-prep.md.
```

`orchestrator_workflow_status` follows the run. To check the script
against the interpreter the floor runs (its MockBackend; no model is
called), point the test at a checkout of the superagent fork with its
dependencies installed:

```sh
# on strix-coordinator, after df -h /; the package lays out jsonc-parser and dsh-util-time beside src/
nix build .#scheduled && cp -r result/share/scheduled "$TMPDIR/sched" && chmod -R u+w "$TMPDIR/sched" && cd "$TMPDIR/sched"
DSH_SUPERAGENT_SRC=<fork checkout> node --experimental-transform-types --test test/day-prep.test.mjs
```

The flake check runs the same file and skips the interpreter tests.

## Journal queries

```sh
journalctl --user -u scheduled-heartbeat -n 20 -o cat
journalctl --user -u dshd@floor.service
```

Lines carry an sd-daemon priority prefix, which journald strips into
`PRIORITY`. The vocabulary is `pass`, `decode`, `withdrawn`, `invalid`,
`floor`, `guard` and `new-agency`. `reason=timer` means systemd fired the
tick; `reason=manual` means it ran any other way. A healthy tick:

```
<6>decode item=master:journal-day due=2026-11-13T05:00:00.000Z result=created
<5>floor action=start state=stopped waiting=1 result=started
<6>pass reason=timer took_ms=412 discover_ms=48 agencies=1 items=3 waiting=1
```

## Failure table

| Symptom | What it means | What to do |
|---|---|---|
| `<4>invalid item=... rev=... at=l:c` | An item fails validation and is skipped. It is logged once per revision. | Fix the file, then `scheduled validate --all` |
| `<5>withdrawn occurrence=... reason=disabled\|removed\|invalid` | A waiting record of an item that is no longer valid and enabled was withdrawn | Intended |
| `<4>floor masked waiting=N` | The floor unit is masked; records wait | Unmask deliberately, or accept that the floor is off |
| `<3>floor action=start state=failed child=...` | The floor crashed. The tick restarted it and exits 1 anyway, so the crash is seen. | `journalctl --user -u dshd@floor.service`, fix, check the next tick |
| `<3>floor state=not-found waiting=N` | No `floor` instance exists and records wait | Create it (commissioning step 3) |
| `<3>floor state=orphaned\|inconsistent ... remedy=...` | dshd reports a broken instance | Follow dshd's remedy; inspect with `dshd get --json floor` |
| `<3>floor state=unavailable error=...` | dshd could not be asked | Check dshd and the user manager |
| `<3>guard machine-id differs: state from another host` | `~/.local/state/scheduled` came from a different machine | Restore the local state; never share it between hosts |
| `<4>clock went back` | The clock is behind `lastTick` | Nothing is handed off; `lastTick` is kept |
| records stay in the inbox | The floor's Source is not reading | `dshd get --json floor`; the Source moves each record to `.done/` or `.bad/` |
| `.bad/<name>.error` | The Source refused a record | `scheduled history ID` shows the error |

The user-unit tripwire sees the heartbeat's exit 1 as a failed start job,
so a refused tick surfaces. The tick never runs `reset-failed`.

## Rollback

Any step back is the previous NixOS generation: it removes the units and
the program and leaves `~/.agency` untouched. To quiet things without a
generation switch, use one of these:
- `scheduled set ID enabled false` for an item;
- stop the timer through Home Manager;
- `dshd stop floor`, which leaves records waiting.

Waiting records of a disabled item are withdrawn at the next tick while
the floor is stopped.

## State at install

Every item ships with `"enabled": false`. The heartbeat ticks, writes no
record and starts nothing, so nothing runs unattended before Tom enables
an item. `floor-upkeep` is copied but inert: the `upkeep` verb its
prompt names belonged to a withdrawn fork branch.
