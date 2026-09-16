# cubs-halogen-probe-1: the `cubs-iteration` executable and the CUBS kit entries

Written 2026-09-16 for the FRONT-12 bootstrap (dotfiles PR "cubs-halogen-probe-1:
cubs-iteration executable and kit entries"). What this repository ships for
the campaign, what it writes, how it exits, and the two acts only Tom takes.
The campaign itself — brief, cards, bundles, worklists, graders, the plan
script — lives in `~/mecattaf/cubs-campaign` and is not in this repository.

MEASURED = observed on the coordinator or in a file today; INFERRED = derived
from code, not exercised.

## What the campaign is, in one paragraph

A 7-day capability probe of Halogen Flash (Qwen3.8-Flash-Next on
`worker:8731`) on the CUBS tree under `~/agency`, run as a serial backlog of
bounded ~40-minute iterations the rewrite kernel admits on the `gpu-worker`
row. The acceptor mints N independent `agent()` items labelled `build:CUBS-<n>`
in one `parallel()`; the lake proposes them one at a time (level 1, cap 1);
the uplink resolves each label against the coordinator's kit and the kernel
runs the argv the kit names under a 2400 s lease. Every task carries a stated
prior and a falsifiable prediction; the mechanical verdict is a validation
command's exit code; Tom reviews every morning and arms the next day's
worklist. Termination of a task or a package is a legitimate outcome.

## The three orchestrator defaults

1. **Routing via `executor: review`** on the cards, so the deployed lake floor
   (`apps/worker/src/floor.ts:87-125`, class match exact) lands the items on
   `gpu-worker` without a Worker redeploy. An `execute`-class member on
   `gpu-worker` is deferred (below).
2. **Envelope-pass semantics.** With no `--evaluator-lock` on the served
   kernel, an item that finishes inside its lease closes `pass` on the lake
   regardless of exit code (`docs/executor.md:44-47`). The campaign's PROOF is
   therefore the commit on the task branch, `receipt.json`, and the usage
   line, never the lake verdict. The executable never fabricates a pass: a
   dead Halogen is an `outage` receipt, a red gate is a `fail` receipt.
3. **`--level 1`** (WIP cap 1): strictly serial, one of the 3N cells in flight.

## The executable: `cubs-iteration`

`pkgs/cubs-iteration/` — a `writeShellApplication` (the derivation's
shellcheck pass is its cheapest oracle) carrying bash, coreutils, curl,
findutils, gawk, git, gnugrep, gnused, jq, python3 with pytest (the
campaign's STDIN-CONTRACT: validation commands are written against a normal
PATH and WP7's graders are pytest), util-linux (`flock`) and
`pkgs.llm-agents.pi`, plus `cubs-helpers.py` (the event-stream
summariser and the built-in diff guard). It is the argv of every
`build:CUBS-<n>` kit entry.

**Why the store `pi` and not `home/pi.nix`'s wrapper.** The wrapper's only
work is to prepend the extension roster to interactive runs, and the roster
is empty (`home/pi.nix` `extensions = { }`; MEASURED: the installed wrapper
execs the store `pi` with no flags). The script runs Pi with
`--no-extensions` and a campaign-private `PI_CODING_AGENT_DIR`, so the kit
carries the derivation the wrapper wraps.

**The child's environment is empty.** The kernel spawns the argv with
`env_clear` and the entry's empty `env_allowlist` (tally
`crates/tally-kernel/src/exec.rs:681-689`): the process sees
`TALLY_EXECUTION_ID` and `TALLY_USAGE_SOURCE_PATH` and nothing else. MEASURED:
`env -i /bin/sh -c 'echo $PATH'` → `/no-such-path`; `getent` and `compgen`
are absent under the store bash. So the script derives HOME from the passwd
entry through its own python3, carries every tool as a store path, and
appends `/etc/profiles/per-user/tom/bin:/run/current-system/sw/bin` LAST for
a validation command that reaches for `nix develop` (home/tally-filler.nix's
reasoning: a second pinned nix would be this repository deciding which nix
another tree's oracle runs).

**One run, in order.**

1. Read ONE JSON object on stdin: the kit's pointer
   `{"worklist": <jsonl>, "id": "CUBS-<n>"}` (resolved to the worklist line
   with that id) or a full task line. Fields: `id`, `package`, `title`,
   `repo` (a subdirectory of `~/agency`, each of which is its own git
   repository — MEASURED: `~/agency` itself is not one), `bundle_path`
   (absolute, `~/`, or relative to the campaign repo), `setup_cmd`
   (string or null), `validation_cmd`, `allowed_paths`, `new_files`
   (non-empty adds the `write` tool), `thinking`, `prior_p_pass`,
   `predicted_failure`. A malformed object exits 65 naming the field.
2. `flock` on `~/.local/state/cubs-campaign/lock`; if `tasks/<id>/receipt.json`
   already says `pass`, exit 0 without running anything (the receipt is the
   done marker, `drain.sh` l.112).
3. The fuse gate, KEYED BY PACKAGE: the master `<state>/fuse` ≥ 3 (Tom's
   stop switch, every package) or this task's `<state>/fuse.d/<package>` ≥ 3 →
   receipt `fuse` with `censored: true`, exit 2, no Pi. A blown package
   retires only its own remaining items.
4. Preflight: campaign dir, `skill/system-prompt.md`, `pi/models.json`
   declaring provider `halogen` with model `halogen-qwen3.8-flash-next`,
   `pi/settings.json` (compaction `reserveTokens` / `keepRecentTokens` live
   there, not in models.json), the bundle, the repo. Missing → exit 78, no receipt, the task stays runnable.
   A `pending` receipt is written here.
5. Poll `GET worker:8731/health` (`curl --max-time 5`) every 10 s until
   `status ok`, `busy false`, `engine.responds`; after 20 min → receipt
   `outage`, exit 69. Record the id
   from `/v1/models` and `/health.version`.
6. `git worktree add` of `~/agency/<repo>` at its current HEAD on branch
   `campaign/cubs-halogen-probe-1/<id>` under `<state>/worktrees/<id>`. A
   retry reuses the worktree: the base sha is persisted, and a WIP commit a
   cancel left on the branch is parked under `refs/cubs-wip/<id>/<epoch>` and
   `reset --mixed` back into the working tree, so HEAD is the base again.
7. `setup_cmd`, if any, inside the worktree (10 min timeout).
8. ONE fresh Pi process:
   `pi -p --mode json --session-dir <state>/sessions --session-id <id>-a1
   --provider halogen --model halogen-qwen3.8-flash-next --thinking <task>
   --no-extensions --no-skills --no-prompt-templates --no-context-files
   --no-approve --tools read,bash,edit,grep,find,ls[,write]
   --system-prompt "<skill/system-prompt.md>" -- "<bundle>"`, with
   `PI_CODING_AGENT_DIR=~/mecattaf/cubs-campaign/pi`, `PI_TELEMETRY=0`,
   `PI_OFFLINE=1`, stdin from `/dev/null` (`pi -p` reads a non-TTY stdin
   to EOF as prompt text — the task JSON was this process's stdin and is
   read in full first), under `timeout -k 30 1200` (the repair process
   `-k 30 900`: a dropped Halogen connection leaves Pi's own auto-retry
   hanging, so the budget is the rail), events streamed to
   `<state>/logs/<id>-a1.jsonl`. A session id that already exists in the
   session dir is rotated (`<id>-a1-r2`) rather than resumed: one fresh
   process, always. Pi's "No project session found with id …; creating a
   new session" stderr line is the expected first-run notice.
9. The diff guard: the campaign's `tools/spec-diff-guard.sh --task <id>
   --worklist <wl> --upstream ~/agency/<repo>` when it exists (allowed paths
   + new files, any `spec.md` frozen, the constitution frozen, `git diff
   --check`, a setup copy identical to upstream is not a change, an empty
   allowed diff fails); the built-in `cubs-helpers.py guard` with the same
   path rules otherwise. Both read untracked files (`ls-files --others`).
   Then the trailing-newline gate over the allowed touched files: `git diff
   --check` does not report a missing final newline, and the smoke showed
   Flash-Next's `edit` dropping it.
10. `validation_cmd` inside the worktree, `timeout 600`, transcript to
    `<state>/logs/<id>-v1.log`.
11. On a red guard or validation: exactly ONE repair — a fresh Pi process
    (`<id>-a2`) fed the bundle, the guard's output, the diff (≤ 24 KB) and the
    transcript tail (≤ 8 KB), never the first process's narration — then the
    guard and validation again, then fail closed.
12. Pass: stage ONLY the files inside `allowed_paths + new_files`, commit
    `"<id>: <title>"` (identity `cubs-iteration`, body naming the bundle and
    skill digests, model, repair count, execution id). Never a push.
13. Receipt, `ledger.jsonl` line, usage line; THIS PACKAGE's fuse
    (`<state>/fuse.d/<package>`) reset to 0 on pass, incremented on fail,
    untouched on outage or cancel. No other package's counter moves, and the
    master `<state>/fuse` is never written by the executable.

**SIGTERM** (the lease's rail: SIGTERM, 30 s checkpoint grace, SIGKILL): the
trap kills the running child (5 s, then KILL), stages and commits the allowed
files as `"<id>: <title> [WIP, cancelled under lease]"`, parks the commit
under `refs/cubs-wip/<id>/…`, writes a `cancelled` receipt and exits 143.
MEASURED in the probe: rc 143 in 137 ms with Pi mid-run.

**Never touched:** `~/.local/state/tally-rewrite` (the usage line goes where
the kernel's resolved `TALLY_USAGE_SOURCE_PATH` says), the kernel socket, the
lake, any `spec/**/spec.md`, any remote.

### `--dry` and `--help`

`--dry` validates stdin and prints the plan as JSON (pi argv, worktree,
branch, guard, validation, preflight booleans, receipt status, both fuse
counts and their paths)
without touching the state dir. MEASURED with the kit's own stdin under
`env -i TALLY_EXECUTION_ID=e TALLY_USAGE_SOURCE_PATH=/dev/null`: rc 0,
`resolved: false` naming the missing `worklists/current.jsonl` while the
campaign repo has none. `--help` prints the contract and the exit codes.

### The receipt (`<state>/tasks/<id>/receipt.json`)

The campaign's `tools/receipt.schema.json` shape, field for field, plus two
the executable adds:

| field | source |
|---|---|
| `schema_version` 1, `task`, `package`, `repo` | the worklist line |
| `provider` halogen, `model` | `/v1/models` at task start, never the worklist |
| `health_version` | `/health.version` rendered `"api X engine Y"` |
| `campaign_sha`, `skill_digest`, `bundle_digest` | campaign HEAD; `sha256:` of the prompt and bundle bytes. All three are null on a censored item, which never reached the preflight |
| `worktree_branch`, `worktree_path`, `base_sha` | the worktree |
| `tool_calls`, `is_error_count`, `repeated_identical_calls`, `tool_call_names` | `tool_execution_start/end` events, summed over both Pi processes; `tool_call_names.bash` is the bash count (the "validation command only" invariant is soft, so it is counted, not enforced); per attempt in `attempts.json` |
| `usage.{prompt_tokens, completion_tokens, reasoning_tokens, message_end_events}` | summed over `message_end` events (pi `Usage` input+cacheRead+cacheWrite / output / reasoning). The smoke found only `--thinking off` is a real cap on Flash-Next (low/medium barely move reasoning), so `task.thinking` stays the switch and the reasoning count is what the ledger reads |
| `diff_sha256` | sha256 of the allowed-files diff at commit time; null when empty |
| `commit_sha` | the one commit on the task branch, or null |
| `validation.{cmd, exit, transcript_digest, seconds, transcript_path, guard_exit}` | the last validation run and the guard's exit |
| `repair_count` 0 or 1, `terminal_status` pending/pass/fail/timeout/outage/fuse/cancelled, `wall_seconds` | the run |
| `prior_p_pass`, `predicted_failure` | copied from the worklist line |
| `observed_failure_mode` | null: the morning review's cell |
| `notes` | the executable's mechanical reading (`diff_guard: …`, `validation_failed (exit N)`, `outage_before_start`, `fuse_blown_before_start (master fuse …, or package WPn …)`, `cancelled …`) |
| `censored` | ADDED: true exactly on an UNRUN item — one a blown fuse (its package's, or the master) retired before it started, so no Pi process saw it. The task that BLEW the fuse ran and is `censored: false` with `terminal_status: fuse`. `jq -s '[.[]|select(.censored)]|length'` over the receipts is the count of items the campaign never attempted |
| `sessions` | the Pi session ids |
| `bash_call_count` | `bash` tool calls summed over both Pi processes |
| `stray_files` | untracked, non-ignored files outside allowed_paths + new_files at close (the guard fails on them; listed so the review sees what the model tried to create) |
| `reasoning_tokens` | top-level mirror of `usage.reasoning_tokens` for the ledger |
| `attempts_path` | `tasks/<id>/attempts.json` |
| `execution_id`, `exit_code` | ADDED: the kernel's `TALLY_EXECUTION_ID`; the exit the receipt describes |

Per-attempt detail (events summary, guard, validation per attempt) is in
`attempts.json` beside it. The usage line appended at
`$TALLY_USAGE_SOURCE_PATH` is
`{"kind":"halogen-usage/1","execution_id","task","model","usage","seconds","terminal_status"}`,
so the kernel's `witness_record.usage_source` points at an artifact that
names the execution back (the LOCAL-SMOKE join, over a real run).

### Exit codes

| rc | meaning | receipt | fuse |
|---|---|---|---|
| 0 | pass, or an idempotent no-op on a passed task | `pass` | this package reset to 0 |
| 1 | fail: setup, guard or validation red after the one repair | `fail` | this package +1 |
| 124 | a Pi process hit its wall-clock budget (1200 s first attempt, 900 s repair); no repair is attempted after a timed-out first attempt | `timeout` | unchanged |
| 2 | fuse: the third consecutive fail IN THIS TASK'S PACKAGE, or a fuse (package or master) already blown | `fuse`, `censored: true` when it was already blown | this package +1 / unchanged |
| 64 | usage | none | — |
| 65 | the stdin JSON or worklist line is malformed | none | — |
| 69 | outage: Halogen not ok/idle within 20 min, or gone mid-run | `outage` | unchanged |
| 75 | another cubs-iteration holds the lock | none | — |
| 78 | campaign material missing | none (a `pending` one may exist) | — |
| 143 | cancelled by SIGTERM/SIGINT | `cancelled` | unchanged |

The fuse is keyed by package: `~/.local/state/cubs-campaign/fuse.d/<package>`
counts the consecutive failures of one work package and, at 3, retires that
package's remaining items and nobody else's — three bad WP1 items leave WP2,
WP3 and WP7 running, which is the whole point of the change (with one global
counter, day one's 28 items completed with ~17% probability).
`~/.local/state/cubs-campaign/fuse` stays the MASTER fuse, read and never
written by the executable, so the stop procedure `echo 3 >
~/.local/state/cubs-campaign/fuse` still halts every package at once
(RETURN-CHECKLIST (g)). Either fuse is reset by removing its file (Tom's act
in the morning review). Because every non-pass exit still "finishes inside
the lease", the lake closes the item `pass` either way (default 2 above); a
blown package therefore burns through ITS remaining items in minutes with
`fuse` receipts carrying `censored: true`, each of which is re-runnable once
the fuse is reset and the plan re-armed.

## The kit entries (`home/tally-uplink.nix`)

600 generated entries beside the untouched LOCAL-SMOKE trio, N = 200
(a label ceiling sized for campaign days 1-7 without a second switch):

| ref | argv | cwd | env_allowlist | usage_source | stdin |
|---|---|---|---|---|---|
| `build:CUBS-<n>` | `<store>/bin/cubs-iteration` | `~/mecattaf/cubs-campaign` | `[]` | `halogen-usage/1`, `<rewrite state>/uplink/usage/cubs-*.jsonl` | `{"id":"CUBS-<n>","worklist":"~/mecattaf/cubs-campaign/worklists/current.jsonl"}` |
| `scope(build:CUBS-<n>)`, `eval(build:CUBS-<n>)` | `/bin/sh -c true` | `/` | `[]` | `opaque-noop/1` | `""` |

**Why stdin is a pointer.** A kit entry's `stdin` is static bytes in the
store kit file: the lake's `readKit` returns the entry as written
(`apps/uplink/src/kit.mjs`), the uplink hands `entry.stdin ?? ""` to
`exec.run` (`apps/uplink/src/uplink.mjs:623`), and the kernel writes it to
the child after its start marker (`exec.rs:747`). The lake's e2e kit does put
the whole item JSON there (`tools/e2e-check.mjs:414-470`), but that kit is
materialised per run by a script; this one is a reviewed store artifact that
a day's worklist must not force a switch to change. Nothing the acceptor's
expansion provides reaches stdin: `argv_ref` is the label
(`packages/planning/src/objects/factory.ts:621`) and the brief goes to the
lake. So the entry names the worklist and the id, and `current.jsonl` is
what the morning review re-points.

MEASURED 2026-09-16: `nix eval …services.tally-uplink.kit` →
`/nix/store/…-tally-uplink-kit.json` with 123 entries;
`nix build .#checks.x86_64-linux.tally-uplink-topology` → rc 0 (the check
does not enumerate kit refs, so it needed no edit);
`tests/tally-uplink/probe-FT-3-kit.sh` K1–K6 green, K7 red only because
`nix flake check --offline --no-build` is red on the untouched `main` checkout
today with the same error (a `source.drv` dependency that cannot be built
offline) — pre-existing, not this change.

## MEASURED: one real run against Halogen (2026-09-16 09:24Z)

The built executable, under `env -i` with only the two `TALLY_` variables
and the scratch overrides (a scratch campaign dir carrying the real
`skill/system-prompt.md` and a `pi/models.json` copied from
`~/.pi/agent/models.json` with the compat fix applied; a scratch git repo;
a scratch state dir; nothing on the box touched), on a one-line dictated
edit with `--thinking low`:

| | |
|---|---|
| wall | 17 s (health poll 1 s, Pi 15 s, validation < 1 s) |
| Pi tool calls | 4 (`read`, `edit` with exact oldText/newText, `bash` × 2 running the named validation command), 0 `isError`, 0 repeats |
| usage summed over 5 assistant `message_end` events | prompt 12337, completion 405, reasoning 74 (pi's `Usage` carries `reasoning`; per turn 10–21 tokens, INFERRED consistent with `reasoning_effort low` reaching the wire, not confirmed from the worker's journal) |
| gate | guard exit 0, `grep -qx hello src/hello.txt` exit 0, first try |
| artifacts | commit `CUBS-SMOKE-1: …` on the task branch, `receipt.json` `pass`, one usage line naming `execution_id smoke-exec-1` |
| model / version read at start | `halogen-qwen3.8-flash-next`, `api 0.7.0 engine 0.7.0` |
| Pi's final message | the bundle's output skeleton, filled (`VALIDATION: … EXIT: 0 FILES: src/hello.txt`) |

This is the first Pi-with-tools run against Halogen recorded on this box
(the harness report found none), and it is a smoke, not a capability claim.

## The oracle

`bash tests/tally-uplink/probe-cubs-iteration.sh` — hermetic: a stub Pi that
emits a `--mode json` event stream and performs a scripted edit, a stub
Halogen (`python3 -m http.server` answering `/health` and `/v1/models`),
throwaway git repos as the CUBS tree, nothing under `~/.local/state` or
`~/agency`. Clauses C1–C11: usage and exit codes; `env -i --dry` on the kit's
own stdin; pass with commit, usage line, ledger line, idempotent rerun; fail
plus one repair with the repair prompt carrying diff and transcript; the fuse
and its reset; the PER-PACKAGE fuse (three forced fails in package A leave
package B running, the master fuse still stops both, and the `censored`
receipts equal the unrun items); the `spec.md` guard; outage without touching
the fuse;
SIGTERM → WIP commit + `cancelled` receipt inside 25 s and a clean retry that
rotates the session id and leaves ONE commit above the base; the events
summariser; `readKit` over all 600 refs with LOCAL-SMOKE kept and
`claude:headless` / `build:CUBS-201` refused; the topology check.
MEASURED 2026-09-16: `PROBE cubs-iteration: PASS`.

## The two operator acts left to Tom

1. **The coordinator switch** (`nixos-rebuild switch` from the merged
   branch): installs the kit with the 120 entries so the first proposal
   resolves — an unresolvable `argv_ref` is a `KitError` that ends the wake
   with the item left `released` (`kit.mjs:56`, `uplink.mjs:616`). Until the
   switch, the entries exist in a store file the running unit does not read.
2. **The non-dry arm** (`tally-plan-arm … --level 1` against the deployed lake
   with `LAKE_TOKEN` read from `~/.local/state/tally-rewrite/lake-token` in
   the shell, never echoed) after the dry run shows `needs: review`, 3N
   items and `pending: null`. `services.tally-uplink.plan` stays null
   (DF-U-D14-3): arming is Tom's act, not this module's.

Before either: `worklists/current.jsonl`, `pi/models.json` and the day-01
bundles must exist in the campaign repo (the executable exits 78 naming the
missing file otherwise), and the ~5-minute scratch-repo smoke of Pi with
tools against Halogen (the halogen-harness report's mandatory step) should
have been read.

## DEFERRED

| id | deferred | why it is barred here | who takes it, and when |
|---|---|---|---|
| DF-CUBS-1 | `--evaluator-lock` on the served kernel, so the lake's verdict and token cells mean something for the campaign | DF-U-D13-2 still stands; with no lock every item that finishes inside its lease is `pass` on the lake. The campaign's proof is the commit + receipt + usage line by design, so the lock is not on the critical path | Tom, with the tally-ts-sdk `apps/evaluator` delivery; then a pin of the lock in `modules/tally-b.nix` |
| DF-CUBS-2 | A floor redeploy adding an `execute`-class member on `gpu-worker` (and the CUBS namespace), so the cards can say `executor: execute` | The deployed Worker routes `execute` to `gpu-coordinator` only (`floor.ts:87-125`); `executor: review` on the cards lands the items on `gpu-worker` today without a redeploy (default 1). A redeploy is `wrangler deploy` under the TL-13 credential and a pin bump | Tom, if the routing workaround is refused; `docs/deploy.md:305-326` |
| DF-CUBS-3 | Correcting the `gpu-worker` row's `context_window 32768` in `modules/tally-b.nix:583-589` (Halogen serves 262144) | Informational only: nothing admits on it (`docs/rows.md:353-368`), and changing a served row is a kernel-visible edit the campaign does not need | A reviewed edit to `modules/tally-b.nix` after the campaign's first day, if anything starts reading the cell |
| DF-CUBS-4 | The `thinkingFormat "qwen"` + `supportsReasoningEffort true` compat fix in `home/pi.nix`'s halogen provider, so `--thinking low` reaches the wire for every Pi user on the box | Shipped campaign-private in `~/mecattaf/cubs-campaign/pi/models.json` (the `judge.sh` precedent) so no switch is needed and receipts still quote the same provider/model pair. Editing `home/pi.nix` changes every interactive Pi session and needs a home-manager switch | Tom, after the campaign's `message_end` usage or the worker's `serve_api:` journal line confirms the effort actually arrives; then a reviewed edit to `home/pi.nix` |
| DF-CUBS-5 | Wiring `cubs-iteration` into `home/tally-uplink.nix`'s kit from `home/pi.nix`'s wrapper rather than from `pkgs.llm-agents.pi` | The wrapper is a `let` binding, not an exported package, and its roster is empty; exporting it is a pi.nix change with no behavioural gain while `--no-extensions` is fixed | A later unit if the roster stops being empty and a campaign wants it |
