# Scheduled

Scheduled is work that happens later, on a cron time, without a systemd
timer per job. The dotfiles declare exactly one clock for it: the
`scheduled-heartbeat.service`/`.timer` pair (D52, hourly, OnStartupSec
2min, Persistent, `home/scheduled.nix`, on the brain host, the NAS).

The heartbeat is a nudger. Each tick:
- reads the item files at `<agency>/.agency/scheduled/<item>.jsonc` (one
  item per file; the master agency is `~`);
- decodes their cron times against the present hour;
- links one occurrence record per due item into the superagent's inbox;
- starts the floor's systemd user unit, named by `SCHEDULED_FLOOR_UNIT`,
  when records wait and the unit is stopped or failed. While no unit is
  named it wakes nothing ([No floor configured](#no-floor-configured)).

It holds no superagent logic. The floor's scheduled Source turns each
record into work, and the floor decides what, if anything, to do. The
heartbeat never:
- stops, restarts, reloads or masks the floor unit, or waits for it;
- calls the floor's HTTP API;
- opens `orchestrator.sqlite`;
- runs a command from an item.

The floor itself stays free of clocks ("NO SCHEDULES EVER"): this
heartbeat is the one clock, and it only links records and starts one
unit. Workflow scripts start on the floor, never from an item. The floor
meant for it is the factory floor (`factory-floor.service` from
`home/factory-floor.nix`, the `agency` CLI). The Master superagent on
dshd that this heartbeat woke until then (`dshd@floor`) was retired on
2026-11-26, with dshd and the Master dsh profiles.

## From the seat: the first item

Run these on the NAS as the user who owns the agencies. The `scheduled`
program and the environment it needs (`SCHEDULED_INBOX`, and
`SCHEDULED_FLOOR_UNIT` once a floor unit is named) come together: the
installed command carries them as defaults (a wrapper), so Claude Code, a
Herdr or hc pane and a plain shell all reach the same inbox and floor
with nothing exported. Herdr panes and Claude Code never run a login
shell, so Home Manager's session variables cannot be relied on there; the
wrapper does not need them. A variable set by hand still wins.

```sh
scheduled new master:weekly-review --cron '0 7 * * 1' --tz Europe/Paris \
  --prompt 'List the open pull requests of the repositories under ~/src and say which need me.'
scheduled show master:weekly-review -n 3   # the next three instants, in UTC
scheduled run master:weekly-review          # try it now, while it is still off
scheduled history master:weekly-review      # the floor received it (done) or refused it (bad)
scheduled set master:weekly-review enabled true   # arm it
```

1. `new` writes `~/.agency/scheduled/weekly-review.jsonc` with
   `"enabled": false`. A new item is always off.
2. `run` writes one manual record into the inbox and starts the floor
   unit if one is named and it is stopped. It does not wait for the work.
   With no floor unit it says so, and the record waits in the inbox.
3. Read the result where the work went
   ([Where the results are](#where-the-results-are)).
4. When the trial run did what was meant, arm the item. The first
   hourly tick that sees it armed fires nothing; its first occurrence is
   the first due instant after that tick. Arm at least an hour before
   the first instant you want: armed at 06:30, an item due at 07:00
   first runs at its next instant after 07:00.

Another agency is any folder with a `.agency/` directory, up to three
levels below `~`. Its id is its path relative to `~`:

```sh
mkdir -p ~/work/acme/.agency/prompts        # the agency, and the prompt file, exist first
$EDITOR ~/work/acme/.agency/prompts/nightly-tests.md
scheduled new work/acme:nightly-tests --cron '0 3 * * *' --tz Europe/Paris \
  --prompt-file .agency/prompts/nightly-tests.md
```

That item runs with `~/work/acme` as its working directory. A
`prompt-file` is relative to the agency folder, must exist and stay
inside it, and is read again at every tick, so editing the prompt file
changes the next occurrence.

## An item

```jsonc
// ~/.agency/scheduled/weekly-review.jsonc
{
  "$schema": "scheduled-item.v1",
  "name": "Weekly review",                    // optional; defaults to the file stem
  "enabled": false,                           // required: false writes no record
  "on": { "schedule": [{ "cron": "0 7 * * 1", "timezone": "Europe/Paris" }] },
  "job": {
    "prompt": [                               // a string, or lines joined with \n
      "List the open pull requests of the repositories under ~/src.",
      "Say which need me, and why. Change nothing."
    ]
  }
}
```

| Key | Required | Rule |
|---|---|---|
| `enabled` | yes | `true` or `false`, no default. `false`: the tick writes no record for it and withdraws a waiting one; `scheduled run` still works |
| `on.schedule` | yes | 1–8 entries `{ "cron", "timezone" }`. Five-field cron; an IANA zone per entry. Instants closer than 60 min across all entries are an error (`density`), a cron that never fires is an error (`never`), a DST gap is a warning (`dst-gap`) |
| `job.prompt` or `job.prompt-file` | exactly one | 1 B–32 KiB of UTF-8. The text is frozen into each record when it is written |
| `name` | no | 1–80 characters, the display title |
| `$schema`, `x-*` | no | ignored, kept |

The file name is the item id: `^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$`.
The file, `scheduled/` and `.agency/` must belong to the user the heartbeat
runs as and not be group- or world-writable, because an item's work runs with full permissions.

Any condition, outcome check, hold or context goes into `job.prompt` in
words: the main Session judges it when the occurrence arrives ("skip if
the journal for that date already exists", "only on workdays"). Keys
that tried to do this are errors that name where their intent now goes:
- `if`, `window`, `outcome`, `hold`, `context`;
- `concurrency`, `permissions`;
- `on.workflow_dispatch` (use `scheduled run`);
- `job.cwd` (the agency folder is the working directory), `job.timeout`.

`model`, `profile`, `priority`, `pair`, `env` and `secrets` are refused:
scheduled work runs on the floor's default pair, and priority is the
superagent's judgement. `workflow` is refused too; to run a workflow
script on a schedule, see [Starting a workflow from an
item](#starting-a-workflow-from-an-item).

Prefer `:00` minutes, and never 02:00–02:59 in Europe/Paris: that hour
is skipped or repeated at a DST change.

## What happens when it is due

1. **The tick.** The timer fires at every full hour. A tick missed
   while the NAS was off runs when the user manager starts again
   (`Persistent`).
2. **Latest only.** For each valid, enabled item the tick collects every
   due instant since the last tick (or since the item was armed). It
   writes one record, for the latest, and counts the rest in `missed`.
   An hourly item after a 3-hour outage gives one record with
   `missed: 2`, never three runs. A floor's Source applies the same rule
   when it reads (the occurrence-record contract): of two waiting records
   of one item, only the newest becomes work.
3. **The record.** One JSON file, occurrence record v1, is linked into
   `<stateDir>/inbox/scheduled/` as
   `<namespace>~<item>@<yyyymmddThhmmZ>.json`. It carries the agency
   folder (`cwd`), the item file, the revision and the prompt text as
   read now.
4. **The wake.** If records wait and the floor unit is stopped (or
   failed), the tick runs `systemctl --user start --no-block <unit>`.
   It queues the start job and does not wait for it. It never stops,
   restarts or reloads the unit. With no floor unit named, nothing is
   woken and the record waits.
5. **The floor.** Its scheduled Source reads the inbox, turns each
   record into one Trigger, and moves the file to `.done/` (or to `.bad/`
   with a `.error` beside it).
6. **The judgement and the work** are the floor's: its superagent
   assesses the Trigger, and accepts it as work in the agency folder or
   ignores it when the prompt itself says it no longer applies. See the
   factory floor's own documentation (`docs/factory-floor.md`).

An edit to an item takes effect at the next hourly pass, never sooner.
A record already written keeps the text it froze.

## Where the results are

The work is the report: there is no report file and no result table.

| What | Where |
|---|---|
| Did the floor get the record? | `scheduled history [ID]`: `done` or `bad` with the error |
| Is the floor unit up, and why not | `systemctl --user status <unit>`; `journalctl --user -u <unit>` |
| The decision and the work | the floor's own record: the `agency` CLI and the floor's panel (NAS loopback 3082, forwarded to the Zenbook by `scheduled-panel-tunnel`) |
| A Claude worker's full session | `~/.claude-work/projects/<cwd slug>/<session>.jsonl`, the cc2 seat. The slug is the agency path with every `/` and `.` as `-`: `/home/me/work/acme` is `-home-me-work-acme` |

## Failure is passive

Nothing retries and nothing pages. Work that fails is the floor's to
show; the next due occurrence arrives as its own record. A record the
Source refused is in `.bad/` and in `scheduled history`. The heartbeat
itself exits 1 only when it cannot hand off or wake the floor, which the
user-unit tripwire surfaces ([Failure table](#failure-table)). With no
floor unit named, a waiting record is not a fault: the tick exits 0.

## Starting a workflow from an item

A workflow script is not an item and has no key in one. It starts on a
request to the floor's superagent that names the script and the
directory, on a floor that offers `orchestrator_workflow_start`. An item
is such a request when its prompt says so, which is also how a workflow
runs on a schedule:

```jsonc
// ~/work/acme/.agency/scheduled/release-notes.jsonc
{
  "enabled": false,
  "on": { "schedule": [{ "cron": "0 6 * * 5", "timezone": "Europe/Paris" }] },
  "job": {
    "prompt": [
      "This is a request to you, the superagent, not work for a worker. Do not accept it as a ticket.",
      "Call orchestrator_workflow_start with script /home/me/work/acme/release-notes.workflow.js and cwd /home/me/work/acme.",
      "Then ignore this trigger with the reason: started workflow <the run id you got>."
    ]
  }
}
```

`scheduled run work/acme:release-notes` starts it now, once a floor
reads the inbox.

## The pieces

| What | Where |
|---|---|
| Items | `<agency>/.agency/scheduled/<item>.jsonc`, schema v1 (`scheduled schema`) |
| Inbox, written by the heartbeat and by `scheduled run` | `<stateDir>/inbox/scheduled/*.json`, through `.tmp/` |
| Inbox, owned by the floor's Source | `.done/` (received), `.bad/` (refused, with `<name>.error`) |
| Heartbeat state (`heartbeat.json`, `intake.json`, `.tick.lock`) | `~/.local/state/scheduled` (systemd `StateDirectory`) |
| The floor | a systemd user unit named by `SCHEDULED_FLOOR_UNIT`, with its suffix (none tonight; `factory-floor.service` once its wake is on) |
| The skill | `home/dot_claude/skills/scheduled/SKILL.md`, linked into both seats ([below](#the-skill)) |

`<stateDir>` is `~/.agency/state/master`, written literally in
`home/scheduled.nix`. It was the Master profile's dsh-superagent
`stateDir` until that profile was retired on 2026-11-26; the path stays,
so the records Tom's items produce are where a floor's Source can be
pointed. `home/scheduled.nix` passes `SCHEDULED_INBOX` to the service, and
`SCHEDULED_FLOOR_UNIT` only when a floor unit is named. The installed
`scheduled` command carries the same values as defaults (a wrapper),
because Home Manager's session variables reach no NAS shell, Herdr or
Claude Code. A variable set by hand still wins. `tests/scheduled` asserts
the inbox path and the floor variable, and `checks.scheduled-vm` runs
`scheduled run` with no environment.

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
6. Wake, only when records wait and a floor unit is named. One
   `systemctl --user show --property=LoadState,ActiveState,SubState,Result,ExecMainStatus -- <unit>`
   reads it once per tick, before step 5's withdrawal (a live floor
   blocks the withdrawal), and the table decides:

   | `systemctl show` says | State in the line | What the tick does | Exit |
   |---|---|---|---|
   | ActiveState `active`, `reloading`, `refreshing` | running | nothing | 0 |
   | ActiveState `activating` (also `auto-restart`) | starting | nothing | 0 |
   | ActiveState `deactivating` | stopping | nothing | 0 |
   | ActiveState `inactive` | stopped | `systemctl --user start --no-block -- <unit>` | 0, or 1 if systemctl refuses the job |
   | ActiveState `failed` | failed | the same start | 1 |
   | LoadState `masked` | masked | nothing | 0 |
   | LoadState `not-found` | not-found | nothing | 1 |
   | LoadState `bad-setting`, `error`; another ActiveState | that word | nothing | 1 |
   | systemctl fails, or the name is not a full unit name | unavailable | nothing | 1 |

   A unit in motion (active, activating, deactivating) is live whatever
   its LoadState, so a unit whose file vanished while it runs is left
   alone. `--no-block`
   returns once the job is queued: `result=queued` says the start was
   asked for, not that the floor came up. A unit whose `Condition…=`
   fails, or that dies at once, shows at the next tick as stopped or
   failed. `enabled: false` items write no records, so nothing wakes the
   floor until Tom enables an item or runs one by hand.

   The unit name must be a full unit name with a `.service` or `.target`
   suffix (`factory-floor.service`); a glob, a path or a name starting
   with `-` is refused before systemctl runs (`error=invalid-unit-name`),
   because `systemctl start` expands globs and turns a path into a mount
   unit.

## No floor configured

This is the NAS's mode from 2026-11-26 until the factory floor's
heartbeat wake is turned on (`home/factory-floor.nix`, `heartbeatWake`):
`home/scheduled.nix` names no floor unit, so the service and the
installed command carry no `SCHEDULED_FLOOR_UNIT`.

- A due tick links its record into the inbox, logs no `floor` line,
  runs no systemctl and exits 0. The record waits.
- The withdrawal still runs (no floor is reading), so a record of an
  item disabled or removed meanwhile is withdrawn at the next tick.
- `scheduled run ID` writes its record, prints `floor: none`, and says on
  stderr that no floor was woken and the record waits in the inbox.
- Waiting records accumulate, one per item per due instant, until a
  floor reads the inbox.

To try a floor unit by hand without changing the host, pass it:
`scheduled run ID --floor-unit factory-floor.service`.

Record names are `<namespace>~<item>@<yyyymmddThhmmZ>.json` for a
schedule and `<namespace>~<item>@run~<ULID>.json` for a manual run. A `/`
in the namespace is written `+`. The record format (v1) is the fork's;
`pkgs/scheduled/test/fixtures/occurrence-v1.json` is byte-identical to
the fork's `tests/fixtures/scheduled-occurrence-v1.json`.

## Commissioning order

The order matters; each step assumes the previous one landed. Rollback at
any step is the previous NixOS generation; [Rollback](#rollback) says what
that generation still runs.

1. Branch, gates, merge:
   - `nix eval` on the NAS;
   - the `scheduled` and `scheduled-vm` checks on strix-coordinator,
     after `df -h /`;
   - the NAS toplevel build;
   - `switch-to-configuration dry-activate` on the NAS.
2. Switch the NAS, attended. After the switch the timer runs, but
   `ConditionPathIsDirectory` skips every tick until `~/.agency` exists.
3. Declare the floor unit (`home/factory-floor.nix`) and start it once
   by hand. Its scheduled Source reads the heartbeat's inbox
   (`~/.agency/state/master/inbox/scheduled`) by default;
   `home/factory-floor.nix` turns it off with an overlay until the flip
   in `docs/factory-floor.md`.
4. Place the master items, every one with `"enabled": false`. Each is
   `~/.agency/scheduled/<item>.jsonc`, item v1 (`scheduled schema`); an
   item written for an earlier layout is not v1, so rewrite a copy of it
   and leave the original where it is. Write the files by hand, or start
   each with `scheduled new`, which creates the directory and always
   writes `"enabled": false` (a `--prompt-file` must exist first; or
   pass `--prompt TEXT`):

   ```sh
   mkdir -p ~/.agency/scheduled
   scheduled new master:<item> --cron '0 6 * * *' --tz <zone> --prompt-file .agency/prompts/<item>.md
   scheduled validate --all      # exit 0: every item is valid
   scheduled ls                  # every item listed disabled, none invalid
   ```
5. First tick by hand, then read the journal:

   ```sh
   systemctl --user start scheduled-heartbeat.service
   journalctl --user -u scheduled-heartbeat -n 20 -o cat
   ```

   Expect a `pass` line, no `<3>` line, and `heartbeat.json` written.
6. `scheduled run master:<item> --floor-unit factory-floor.service`
   once. One record appears in the inbox, the floor unit starts if it was
   stopped, and the record moves to `.done/`. `scheduled history` lists
   it.
7. Tom turns the heartbeat wake on, which names the floor unit to the
   heartbeat. Only Tom does this.
8. Tom enables an item. Only Tom does this.

## Everyday commands

`ID` is `<agency id>:<item>`; a bare item resolves when exactly one
agency has it.

```sh
scheduled ls [--agency A]            # one row per item: enabled/disabled/invalid, next instant
scheduled show ID [-n N]             # the parsed item, next instants, last records from .done/ and .bad/
scheduled validate --all             # or explicit PATHs, or --stdin --as PATH
scheduled schema                     # the JSON Schema of item v1
scheduled new ID --cron '0 6 * * *' --tz Europe/Paris --prompt TEXT   # always enabled: false
scheduled set ID enabled true        # arm (false to disarm); --expect REV to guard
scheduled set ID on.schedule[0].cron '"0 6 * * 1"'
scheduled set ID name --unset
scheduled rm ID [--expect REV]
scheduled run ID [--json]            # one manual record now, then the wake table
scheduled history [ID] [-n N]        # what the Source received (done) or refused (bad)
```

Writes validate first and refuse invalid text. `set` keeps the file's
comments. A `VALUE` is read as JSON when it parses, else as a string, so
a cron needs its quotes inside the shell quotes. `--expect` compares with
the current revision (the 12 hex `ls` and `show` print). A conflict exits
3 and nothing is written.

`run` works on a disabled item: `enabled: false` cancels only scheduled
occurrences. It does not wait for the work. The superagent's own record
(its Thread and Ticket) is where the work is followed.

`run` and `history` take the inbox from `SCHEDULED_INBOX`, and `run` takes
the floor unit from `SCHEDULED_FLOOR_UNIT`. The installed command defaults
them; set them, or pass `--inbox DIR --floor-unit NAME` to `run`, to
override. Without an inbox, `run` exits 2 and names both ways to give one.
Without a floor unit (unset, or `SCHEDULED_FLOOR_UNIT=` set empty), it
writes the record, prints `floor: none` and says on stderr that it woke no
floor; the record waits in the inbox. The old `SCHEDULED_FLOOR_INSTANCE`,
`--floor-instance` and `SCHEDULED_DSHD` were removed with dshd on
2026-11-26 (scheduled 0.3.0), with no alias.

Exit codes: 0 ok, 1 refused or a fault, 2 usage, 3 revision conflict.

## The skill

Claude Code on either seat knows these rules through the `scheduled`
skill, `home/dot_claude/skills/scheduled/SKILL.md`. On the NAS the seat
skill directories `~/.claude/skills` and `~/.claude-work/skills` are
writable directories that Home Manager does not own
(`hosts/nas/default.nix`), so the skill is linked into each of them as
one entry, `scheduled`, by the same file. Elsewhere the seats link the
whole skill tree (`home/agent-tools.nix`). `tests/nas-agent-host`
asserts both NAS links.

## Journal queries

```sh
journalctl --user -u scheduled-heartbeat -n 20 -o cat
journalctl --user -u factory-floor.service     # the floor unit, once one is named
```

Lines carry an sd-daemon priority prefix, which journald strips into
`PRIORITY`. The vocabulary is `pass`, `decode`, `withdrawn`, `invalid`,
`floor`, `guard` and `new-agency`. `reason=timer` means systemd fired the
tick; `reason=manual` means it ran any other way. A healthy tick:

```
<6>decode item=master:weekly-review due=2026-11-16T06:00:00.000Z result=created
<5>floor action=start unit=factory-floor.service state=stopped waiting=1 result=queued
<6>pass reason=timer took_ms=412 discover_ms=48 agencies=1 items=3 waiting=1
```

With no floor unit named, the same tick has no `floor` line.

## Failure table

| Symptom | What it means | What to do |
|---|---|---|
| `<4>invalid item=... rev=... at=l:c` | An item fails validation and is skipped. It is logged once per revision. | Fix the file, then `scheduled validate --all` |
| `<4>invalid item=... reason=ownership\|file` | An item fails before its bytes are read: not ours, group- or world-writable, not a regular file, over 64 KiB or unreadable. Logged once per error and stat tuple. | `chmod 600` or fix the file; the next tick reads it again |
| `<4>invalid path=... reason=stem\|agency-name\|ownership` | Discovery skipped a file or folder: a stem that is not `[a-z0-9-]`, `~/master/.agency`, or a writable `.agency/`. Logged once. | Rename or fix it |
| `<4>discover unreadable path=... error=...` | A `scheduled/` folder, or a folder above known items, cannot be read. Its items keep their last parse and their waiting records are kept; the tick exits 1. | Restore the folder's permissions or mount |
| `<5>withdrawn occurrence=... reason=disabled\|removed\|invalid` | A waiting record of an item that is no longer valid and enabled was withdrawn | Intended |
| `<4>floor masked waiting=N` | The floor unit is masked; records wait | Unmask deliberately, or accept that the floor is off |
| `<3>floor action=start unit=U state=failed child=...` | The floor unit failed: `child=exit:N` or `signal:N` from its main process, else `result:R`, systemd's Result. The tick queued a start and exits 1 anyway, so the failure is seen. | `journalctl --user -u U`, fix, check the next tick |
| `<3>floor action=start unit=U ... result=failed error=...` | systemctl refused the start job | The error says why; `systemctl --user status U` |
| `<5>floor action=start ... result=queued`, yet the floor is down | The start was only queued (`--no-block`); the unit's condition failed or it died at once | `systemctl --user status U`; the next tick reads it again |
| `<3>floor state=not-found waiting=N` | systemd knows no unit of that name and records wait | Declare the unit, or fix `SCHEDULED_FLOOR_UNIT` |
| `<3>floor state=bad-setting\|error remedy=...` | systemd could not load the unit file | Follow the remedy (`systemctl --user status U`) |
| `<3>floor state=unavailable error=...` | systemctl could not be asked (no user bus), or `error=invalid-unit-name`: the name lacks its suffix or is a glob or path | Check the user manager; name the unit in full |
| `<3>guard machine-id differs: state from another host` | `~/.local/state/scheduled` came from a different machine | Restore the local state; never share it between hosts |
| `<4>clock went back` | The clock is behind `lastTick` | Nothing is handed off; `lastTick` is kept |
| `scheduled tick: --now needs an explicit --state-dir` | A `--now` pass would commit its `lastTick` into the heartbeat's own state | Pass a scratch `--state-dir` |
| records stay in the inbox | No floor reads them: none is named ([No floor configured](#no-floor-configured)), or its Source is off | `scheduled history`; the floor's own status; the Source moves each record to `.done/` or `.bad/` |
| `.bad/<name>.error` | The Source refused a record | `scheduled history ID` shows the error |
| `done` in history, but no work | The floor ignored the occurrence, or it waits for a judgement | The floor's own record of its decision |

The user-unit tripwire sees the heartbeat's exit 1 as a failed start job,
so a refused tick surfaces. The tick never runs `reset-failed`.

## Rollback

Any step back is the previous NixOS generation, and it does not leave
`~/.agency` alone. A generation from before scheduled 0.2.0 runs heartbeat
0.1.0, which reads `.agency/workflows/` and keeps its state under
`~/.agency/state/master`; items under `.agency/scheduled/` are ignored
until you roll forward.

A generation from before 2026-11-26 runs scheduled 0.2.0, whose tick
knows only the retired dshd floor: it starts `dshd@floor` (on loopback
3082) whenever a record waits. Before rolling back across that line,
stop `scheduled-heartbeat.timer` if another floor holds 3082.

To quiet things without a generation switch, use one of these:
- `scheduled set ID enabled false` for an item;
- stop the timer through Home Manager;
- `systemctl --user stop <unit>`, which holds only until a tick finds a
  waiting record: the heartbeat starts a stopped floor unit, even one
  stopped by intent, and `scheduled run` starts it at once. To keep the
  floor down, set the items `enabled false` first, mask the unit (the
  tick then logs `<4>floor masked`), or name no floor unit to the
  heartbeat ([No floor configured](#no-floor-configured)).

Waiting records of a disabled item are withdrawn at the next tick while
the floor is stopped.

## State at install

Nix installs no item. `scheduled new` always writes `"enabled": false`,
and an item placed by hand starts the same way. The heartbeat ticks,
writes no record and starts nothing, so nothing runs unattended before an
item is enabled. The items in `pkgs/scheduled/test/fixtures/master/` are
synthetic examples for the tests, not copies of real ones: real items
live only in their agency's `.agency/scheduled/`.
