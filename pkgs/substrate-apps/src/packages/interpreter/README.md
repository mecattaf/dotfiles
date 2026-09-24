# @substrate/interpreter

Runs a Claude Code ultracode workflow script (`export const meta = ...` plus a body with top-level `await` and
`return`) against a backend, journals every call, and replays or resumes from that journal. It replaces tally-ts-sdk's
`packages/acceptor` and `tally-plan-arm.mjs` (ruling R44; see `DECISIONS.md` at the repo root). This page is the
written contract the acceptor kept in its README and `docs/conversion.md` (parity gap PT-15).

## The realm contract

A script runs in a fresh `node:vm` context created from `Object.create(null)` (`src/sandbox.ts`). It sees the
ECMAScript intrinsics of its own realm and the workflow builtins, nothing else. No `process`, `require`, `fetch`,
`setTimeout`, `performance`, `Buffer`, or any host object. Every builtin is defined inside the realm and talks to the
host through one captured bridge; values cross as JSON strings, and host errors are re-created as realm errors.

Banned, because each would make a resumed run diverge from its journal (each throws
`<what> is not available in a workflow script (it would break resume)`):

| banned | since |
|---|---|
| `Date.now()` | D09 |
| `Date()` called as a function | D09 |
| argless `new Date()` | D09 |
| `Math.random()` | D09 |
| argless `Intl.DateTimeFormat().format()` and `.formatToParts()` | D17 (2026-09-24) |

Pinned to UTC (D17): the default `timeZone` of `Intl.DateTimeFormat`, the `Date#toLocale*String` methods, the Date
local-time accessors (`getHours`, `setHours` and the rest, `getTimezoneOffset`, `toString`, `toDateString`,
`toTimeString`) and the multi-field `new Date(y, m, d, ...)` constructor. `new Date(value)`, `Date.UTC` and
`Date.parse` still work. The guards are non-writable and non-configurable; a script cannot undo them.

Residue (known, not fixed): `Date.parse` of an ISO string without an offset (`"2026-09-23T00:00"`) is read in the host
zone, as ECMAScript specifies. Write the `Z`.

This is isolation of globals and of the host object graph, not a security boundary: `vm` shares the process, the heap
and the event loop. Workflow scripts are the operator's own code.

## Nothing is fabricated

- A replay never reports `completed` after reaching a call its journal did not witness. It reports `diverged`
  (`src/cli.ts`, exit 1). There is no suspension thrown through user code (D02).
- A failed call is journalled with its `error` and can be witnessed as failed (D08).
- A witnessed result is re-checked against the call's schema; a mismatch is a null, never a coerced value (D14).
- A throwing `parallel` thunk or `pipeline` stage becomes `null` for that item only, and is journalled as
  `item_null` with its stage index (D12, D15). The run continues.

## Caps

| cap | value | where |
|---|---|---|
| nesting of `workflow()` | 1 level (depth 2 is refused) | `MAX_NESTING`, `src/interpreter.ts` |
| items per `parallel` / `pipeline` call | 4096 | `ITEMS_PER_CALL_CAP` |
| agent calls in one run's lifetime | 1000 | `LIFETIME_AGENT_CAP` |
| budget | a ceiling: a call that would pass it is refused at admission and journalled (D10) | `--budget` |

## Resume identity

A call's identity is either `chain` (the harness's chained key, the CLI default, for fidelity with the harness journal)
or `content` (`c1:<sha256>#<occurrence>`, `src/key.ts`), selected with `--cache-identity`. The production paths (the
puller and the integrated gate) use `content`, so an early failure does not discard later cached work (D04, D07, D18).

## CLI

`bin/naive-run.mjs <script.js|record.json> [--args <json>] [--backend mock|replay] [--journal <dir>]
[--replay <journal.jsonl>] [--concurrency N] [--budget N] [--max-attempts N] [--cache-identity chain|content]
[--print-result]`. Exit codes: 0 completed; 1 failed or diverged; 2 usage; 3 crash; 4 the final recorded run was
killed. Run any test that spawns it under `~/.local/bin/runtime-test`.
