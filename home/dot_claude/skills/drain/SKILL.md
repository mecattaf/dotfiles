---
name: drain
description: Manually distill the exact current root Claude Code or Codex session into the local Markdown journal through the request-scoped GPU utility model (llama-swap, qwen3.6-35B-A3B; migrated off the decommissioned NPU 2026-08-29). Use only when the user explicitly invokes /drain or $drain, or plainly asks to drain the current session.
---

# Drain the current session

## Where the distillation runs

Drain's distillation used to run on the request-scoped NPU utility model. The
XDNA2 NPU was decommissioned permanently on both Strix Halo boxes on
**2026-08-29** — but the seam MIGRATED rather than retiring. The stable model id
`utility` is now served by the GPU roster: the `utility-model` wrapper forwards
one request to llama-swap, which serves **qwen3.6-35B-A3B** behind that id.

Two practical consequences:

- The wrapper is installed on the **coordinator only**, because that is the only
  host whose llama-swap carries the row. Off that box the command exits 1 with
  `ai-memory: local utility-model is not installed here; the GPU utility model
  (qwen3.6-35B-A3B through llama-swap) is served on the coordinator only`.
  Report that and stop — do not go looking for another engine.
- The **first** request after an idle period cold-loads a ~40 GB model and can
  take minutes. That is expected, not a hang. Let it finish.

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
