# Harvest on close — the SessionEnd hook

MEM-2 (dotfiles#339). Mechanism: `~/sept8/MECHANISM-2026-09-07.md` §6b.
Decisions: `~/research-methods/DECISIONS.md` D-E07, D-E13, D-E14.

## What it is

`home/dot_claude/settings.json` declares two hooks. The first, SessionStart, is
herdr's. The second, added here, is SessionEnd → `bash
'/home/tom/.claude/hooks/ai-memory-harvest.sh'`, and it runs MEM-1's `harvest`
verb over the session that is ending.

The journal stays what Tom chose to keep: a manual `/drain` and nothing else.
The harvest store is a second, machine-written store beside it, and the hook is
the only thing that writes it automatically.

| | journal | harvest store |
|---|---|---|
| written by | `/drain`, only when Tom asks | this hook, on every root session end |
| where | `~/mecattaf/notes/journal` | `~/.local/state/tally-rewrite/harvest` (D-E07) |
| front matter | `drained_at:` | `harvested_at:`, plus `resolved:` (D-E13) |
| one file per | note, deterministic slug | session, `<session_id>.md` |

## The three properties that are not negotiable

`claude` **waits** for a SessionEnd hook before the process exits — MEASURED
2026-09-07: a hook sleeping 15 s made `claude -p 'reply with the single word
ok' --model haiku` take 17 s of wall clock against 2 s without it. Everything
below follows from that wait.

1. **It exits 0 on every path.** A hook that can exit non-zero is a hook that
   can wedge a session end.
2. **Its own timeout fires first.** The script runs the harvest under `timeout
   420` (`AI_MEMORY_HARVEST_HOOK_TIMEOUT` overrides); settings.json declares
   `"timeout": 600`. The script therefore always ends by its own hand, and
   always reaches its last line. The flake check asserts the ordering.
3. **One session end, one log line.** `<harvest dir>/hook.log` gets exactly one
   appended line per invocation, naming the session and what happened:

   ```
   2026-09-07T20:09:37+02:00 session=0748c1ca-…-7e4a876b1328 status=created elapsed=32s created: /…/harvest/0748c1ca-….md
   ```

   `status` is one of `created`, `updated`, `unchanged`, `skipped`, `failed`,
   `timeout`. The log is a ledger, not a transcript.

## What it refuses

Child and subagent sessions, twice over. A transcript under a `subagents/`
directory is refused by name, before python starts. Every other non-root session
is refused by `ai_memory.py`'s own structural proof — the trace must carry a
non-sidechain `user`/`assistant` record under this `session_id` — and that
refusal is surfaced as `status=skipped` with the engine's own reason.

`CLAUDE_CODE_CHILD_SESSION` is **cleared**, not trusted. Claude Code sets it on
the subprocesses of a tool call, so a session started from inside another
session's Bash tool inherits it (MEASURED 2026-09-07), and a hook that believed
it would refuse every such root session. The structural proof stands whatever
the environment says; the flag does not.

## What it never does

It never runs `drain`, never reads or writes the journal, and never touches
branch (a)'s live `~/.local/state/tally` — the string that would name that
directory appears nowhere in the script, and the flake check asserts it.

## Where each piece lives

| piece | path |
|---|---|
| the hook | `home/dot_claude/hooks/ai-memory-harvest.sh` |
| the block that calls it | `home/dot_claude/settings.json`, `hooks.SessionEnd` |
| the delivery | `home/home.nix`, one out-of-store symlink to `~/.claude/hooks/` |
| the verb it runs | `home/dot_claude/skills/drain/scripts/ai_memory.py harvest` |
| the contract tests | `tests/ai-memory-hook/harvest-hook-test.sh` (offline, fake engine) |
| the eval-time asserts | `flake.nix`, `checks.ai-memory-harvest-hook` |
| the end-to-end oracle | `tools/mem-2-hook-oracle.sh` |

## Running the oracle

```bash
bash tools/mem-2-hook-oracle.sh
```

It builds a scratch `CLAUDE_CONFIG_DIR` carrying the rendered settings.json, the
hook script and a link to this checkout's drain skill; borrows the seat's
`.credentials.json` as a **symlink** (never opened, never copied, never
printed); spends one haiku turn; and then asserts the clauses above plus `nix
flake check --offline --no-build`. `MEM2_SEAT_CONFIG_DIR` picks the seat whose
credential is borrowed; `MEM2_KEEP=1` keeps the scratch tree.

## Not in this unit

No `Stop` and no `PreCompact` hook. No hook ever calls the drain. The
SessionStart hook is unchanged. The enqueue-row writer that turns
`unresolved_units` into rows in the live daemon's shape is MEM-3.
