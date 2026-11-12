# Scheduled

Scheduled is work that happens later, on a cron time, without a systemd
timer per job. The dotfiles declare exactly one clock for it: the
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

dshd itself stays free of clocks ("NO SCHEDULES EVER"). The superagent
and its profiles are described in [dsh-master.md](dsh-master.md);
workflow scripts start there, never from an item.

## From the seat: the first item

Run these as Tom's user on the NAS. The `scheduled` program and the two
environment variables it needs (`SCHEDULED_INBOX`,
`SCHEDULED_FLOOR_INSTANCE`) are in every login shell, so Claude Code,
dsh-web's terminal and a plain shell all reach the same inbox and floor.

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
2. `run` writes one manual record into the inbox and starts the floor if
   it is stopped. It does not wait for the work.
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
The file, `scheduled/` and `.agency/` must be Tom's and not group- or
world-writable, because an item's work runs with full permissions.

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
   `missed: 2`, never three runs. The floor applies the same rule when
   it reads: of two waiting records of one item, only the newest becomes
   work.
3. **The record.** One JSON file, occurrence record v1, is linked into
   `<stateDir>/inbox/scheduled/` as
   `<namespace>~<item>@<yyyymmddThhmmZ>.json`. It carries the agency
   folder (`cwd`), the item file, the revision and the prompt text as
   read now.
4. **The wake.** If records wait and the `floor` instance is stopped,
   the tick runs `dshd start floor`. It never reads the instance's
   `enabled` flag, and never stops, restarts or updates it.
5. **The floor.** The scheduled Source reads the inbox every 10 s,
   raises one Trigger per record on its own Thread, and moves the file
   to `.done/` (or to `.bad/` with a `.error` beside it).
6. **The judgement.** The main Session (Claude Opus through dsh-claude,
   accept mode `auto`) assesses the Trigger under the `scheduled` rule
   and accepts it as one Ticket, or ignores it when the prompt itself
   says it no longer applies.
7. **The work.** The Ticket runs as one dshd unit,
   `sa-<words>-a1`, in the agency folder, on the default pair, with full
   permissions. The Ticket ends when the unit ends: exit 0 is completed,
   anything else is failed.

An edit to an item takes effect at the next hourly pass, never sooner.
A record already written keeps the text it froze.

## Where the results are

The work is the report: there is no report file and no result table.

| What | Where |
|---|---|
| Did the floor get the record? | `scheduled history [ID]`: `done` or `bad` with the error |
| Which unit ran it | `dshd ls` lists units named `sa-…-a<k>`; `dshd get --json <unit>` shows the labels `superagent.ticket`, `superagent.assignment` and `superagent.pair`, the cwd and the exit |
| What the worker printed | `dshd read <unit>` (last 200 lines; `-n N`, `-f` while it runs) |
| The worker's full session, Claude pairs | `~/.claude-work/projects/<cwd slug>/<session>.jsonl`, the cc2 seat. The slug is the agency path with every `/` and `.` as `-`: `~/work/acme` is `-home-tom-work-acme` |
| The worker's full session, every pair | `~/.dsh/sessions/--<cwd with / as ->--/session-<id>/session.v4.jsonl` |
| The superagent's decision and the Ticket | the floor's panel (`dshd attach floor`), Trigger and Execution tabs; see [dsh-master.md](dsh-master.md#the-panel) |
| The superagent's own transcript | `~/.claude-work/projects/-home-tom--agency-state-master/`: the main Session works in the `stateDir` |

## Failure is passive

Nothing retries and nothing pages. A worker that exits non-zero leaves a
failed Ticket in the panel and a failed unit in `dshd ls`; the next due
occurrence runs as its own Ticket. An occurrence the superagent ignored
is a Decision with its reason in the panel's Eval tab. A record the
Source refused is in `.bad/` and in `scheduled history`. The heartbeat
itself exits 1 only when it cannot hand off or wake the floor, which the
user-unit tripwire surfaces ([Failure table](#failure-table)).

## Starting a workflow from an item

A workflow script is not an item and has no key in one. It starts on a
request to the superagent that names the script and the directory
([dsh-master.md](dsh-master.md#workflows)). An item is such a request
when its prompt says so, which is also how a workflow runs on a schedule:

```jsonc
// ~/work/acme/.agency/scheduled/release-notes.jsonc
{
  "enabled": false,
  "on": { "schedule": [{ "cron": "0 6 * * 5", "timezone": "Europe/Paris" }] },
  "job": {
    "prompt": [
      "This is a request to you, the superagent, not work for a worker. Do not accept it as a ticket.",
      "Call orchestrator_workflow_start with script /home/tom/work/acme/release-notes.workflow.js and cwd /home/tom/work/acme.",
      "Then ignore this trigger with the reason: started workflow <the run id you got>."
    ]
  }
}
```

`scheduled run work/acme:release-notes` starts it now. This is the start
path the 12 Nov 2026 rehearsal exercises (gate P-W0).

## The pieces

| What | Where |
|---|---|
| Items | `<agency>/.agency/scheduled/<item>.jsonc`, schema v1 (`scheduled schema`) |
| Inbox, written by the heartbeat and by `scheduled run` | `<stateDir>/inbox/scheduled/*.json`, through `.tmp/` |
| Inbox, owned by the floor's Source | `.done/` (received), `.bad/` (refused, with `<name>.error`) |
| Heartbeat state (`heartbeat.json`, `intake.json`, `.tick.lock`) | `~/.local/state/scheduled` (systemd `StateDirectory`) |
| The floor | dshd instance `floor` (`SCHEDULED_FLOOR_INSTANCE`) |
| The skill | `home/dot_claude/skills/scheduled/SKILL.md`, linked into both seats ([below](#the-skill)) |

`<stateDir>` is the Master profile's dsh-superagent `stateDir`
(`programs.dsh.master.stateDir`, default `~/.agency/state/master`), and it
is the one value the two sides share. `home/scheduled.nix` passes
`SCHEDULED_INBOX=<stateDir>/inbox/scheduled` to the service, and the
installed `scheduled` command carries it and the floor instance as defaults
(a wrapper), because Home Manager's session variables reach no NAS shell,
Herdr or Claude Code. A variable set by hand still wins. `tests/scheduled`
asserts that the two agree, and `checks.scheduled-vm` runs `scheduled run`
with no environment.

The floor's DSH profiles, `master` and one `master-<pair>` per worker
pair, are rendered from one source; see [dsh-master.md](dsh-master.md).

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
the floor from `SCHEDULED_FLOOR_INSTANCE`. The installed command defaults
both; set them, or pass `--inbox DIR --floor-instance NAME` to `run`, to
override. Without an inbox, `run` exits 2 and names both ways to give one.
Without a floor instance (say `SCHEDULED_FLOOR_INSTANCE=` set empty), it
writes the record, prints `floor: none` and says on stderr that it woke no
floor; the next tick wakes the floor.

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
| `<4>invalid item=... reason=ownership\|file` | An item fails before its bytes are read: not ours, group- or world-writable, not a regular file, over 64 KiB or unreadable. Logged once per error and stat tuple. | `chmod 600` or fix the file; the next tick reads it again |
| `<4>invalid path=... reason=stem\|agency-name\|ownership` | Discovery skipped a file or folder: a stem that is not `[a-z0-9-]`, `~/master/.agency`, or a writable `.agency/`. Logged once. | Rename or fix it |
| `<4>discover unreadable path=... error=...` | A `scheduled/` folder, or a folder above known items, cannot be read. Its items keep their last parse and their waiting records are kept; the tick exits 1. | Restore the folder's permissions or mount |
| `<5>withdrawn occurrence=... reason=disabled\|removed\|invalid` | A waiting record of an item that is no longer valid and enabled was withdrawn | Intended |
| `<4>floor masked waiting=N` | The floor unit is masked; records wait | Unmask deliberately, or accept that the floor is off |
| `<3>floor action=start state=failed child=...` | The floor crashed. The tick restarted it and exits 1 anyway, so the crash is seen. | `journalctl --user -u dshd@floor.service`, fix, check the next tick |
| `<3>floor state=not-found waiting=N` | No `floor` instance exists and records wait | Create it ([dsh-master.md](dsh-master.md#the-floor-instance)) |
| `<3>floor state=orphaned\|inconsistent ... remedy=...` | dshd reports a broken instance | Follow dshd's remedy; inspect with `dshd get --json floor` |
| `<3>floor state=unavailable error=...` | dshd could not be asked | Check dshd and the user manager |
| `<3>guard machine-id differs: state from another host` | `~/.local/state/scheduled` came from a different machine | Restore the local state; never share it between hosts |
| `<4>clock went back` | The clock is behind `lastTick` | Nothing is handed off; `lastTick` is kept |
| `scheduled tick: --now needs an explicit --state-dir` | A `--now` pass would commit its `lastTick` into the heartbeat's own state | Pass a scratch `--state-dir` |
| records stay in the inbox | The floor's Source is not reading | `dshd get --json floor`; the Source moves each record to `.done/` or `.bad/` |
| `.bad/<name>.error` | The Source refused a record | `scheduled history ID` shows the error |
| `done` in history, but no unit | The superagent ignored the occurrence, or the Trigger waits for an Eval | The panel's Eval tab shows the Decision and its reason |

The user-unit tripwire sees the heartbeat's exit 1 as a failed start job,
so a refused tick surfaces. The tick never runs `reset-failed`.

## Rollback

Any step back is the previous NixOS generation: it removes the units and
the program and leaves `~/.agency` untouched. To quiet things without a
generation switch, use one of these:
- `scheduled set ID enabled false` for an item;
- stop the timer through Home Manager;
- `dshd stop floor`, which holds only until a tick finds a waiting
  record: the heartbeat starts a stopped floor, even one stopped by
  intent, and `scheduled run` starts it at once. To keep the floor down,
  set the items `enabled false` first, or mask the unit (the tick then
  logs `<4>floor masked`).

Waiting records of a disabled item are withdrawn at the next tick while
the floor is stopped.

## State at install

Every item ships with `"enabled": false`. The heartbeat ticks, writes no
record and starts nothing, so nothing runs unattended before Tom enables
an item. `floor-upkeep` is copied but inert: the `upkeep` verb its
prompt names belonged to a withdrawn fork branch.
