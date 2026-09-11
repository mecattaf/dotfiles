---
name: drain
description: Manually distill the exact current root Claude Code or Codex session into the local Markdown journal through the request-scoped GPU utility model (the utility-model wrapper on the coordinator, which forwards one request to the Halogen server on the worker). Use only when the user explicitly invokes /drain or $drain, or plainly asks to drain the current session.
---

# Drain the current session

## Where the distillation runs

Drain's distillation runs on the request-scoped GPU utility model. The stable
model id `utility` is served by the fleet's one inference server: the
`utility-model` wrapper forwards one chat-completions request over the wired
LAN to the **Halogen Flash server on the worker** (`http://worker:8731`,
model id `halogen-qwen3.8-flash-next`), and returns the answer under the
stable id.

Two practical consequences:

- The wrapper is installed on the **coordinator only**. Off that box the
  command exits 1 with `ai-memory: local utility-model is not installed here;
  the utility-model wrapper (which forwards to the Halogen server on the
  worker) is installed on the coordinator only`. Report that and stop — do not
  go looking for another engine.
- The server stays resident, so a request normally answers within its own
  generation time. A request that lands while the worker's unit is still
  starting (a cold start reads ~68 GB off NVMe and is budgeted up to 45
  minutes) waits on that start. That is expected, not a hang. Let it finish.

This is one explicit action. Run:

```bash
python3 "$HOME/.agents/skills/drain/scripts/ai_memory.py" drain
```

Then report the command's exact `created`, `updated`, or `unchanged` result.

Hard boundaries:

- Do not select a session, search for the newest trace, or substitute another
  session when exact current-session resolution fails.
- Do not edit the generated note by hand.
- Do not invoke a main agent, cloud model, or paid fallback if the local
  utility model fails.
- Do not author a handoff, run Git commands, or imply that anything was backed
  up remotely.
- Do not run this automatically at Stop time or as a side effect of another
  skill. The user must request every drain. That prohibition is about the
  journal and it stays; it is lifted only for the separate harvest store below
  (R-c21).

## The harvest verb — the same machinery, a different store

`harvest` is a second verb on the same engine. It shares drain's identity
resolution, trace capture and provenance validation and its utility-model path,
and it differs in exactly one way that matters: it writes to
`~/.local/state/tally-rewrite/harvest/<session_id>.md` — one file per session,
overwritten on a later harvest of the same session — and never to the journal
(D-E07). The journal stays what Tom chose to keep.

```bash
python3 "$HOME/.agents/skills/drain/scripts/ai_memory.py" harvest
```

- It is non-interactive by construction: it never prompts, exits 0 on a written
  file, and otherwise exits non-zero with the reason on stderr. It is what a
  SessionEnd hook calls.
- It never runs the drain, and the drain never runs it.
- Its distillation carries two fields the journal note does not render:
  `resolved` (a boolean the model states, never inferred from prose) and
  `unresolved_units` (each one bounded unit of work in one sentence naming its
  deliverable). Both are required of the model; a missing one is a bounded
  failure, not a guess.

### `harvest --enqueue` — an unresolved unit as a row

```bash
python3 "$HOME/.agents/skills/drain/scripts/ai_memory.py" harvest --enqueue
```

With `--enqueue`, each unresolved unit of the distillation also becomes one row
in the live daemon's enqueue-event shape, written under the harvest store at
`<store>/enqueue/<eventId>.enqueue.json`.

- The shape is the daemon's, key for key: `schemaVersion` 1, a uuid4 `eventId`,
  and a `row` whose `description` is the unit sentence, `source` is `harvest`,
  `adapter` is `ai-memory`, `pool` is `["harvest"]`, `sessionRef` is the session
  id and `dedupKey` is `harvest:<session_id>:<n>`.
- Nothing about a row runs anything: `argv` is empty, `noEnqueue` is true and
  `priority` is `low`. A harvested unit never outranks work Tom released.
- Every row is checked by `tools/enqueue-row-check.py` — whose required keys and
  types are taken from the daemon's own rows — *before* it reaches the disk. A
  row that fails is not written at all, and its reason is one line in the
  store's `hook.log`; the verb then exits non-zero with the same reason on
  stderr, with the harvest note itself still written.
- The rows stay in the harvest store. Moving one into the daemon's own events
  directory is a separate act, not this verb's (D-E07).
- A harvest that changed nothing writes no rows again, so a SessionEnd hook that
  fires twice does not enqueue the same units twice.
