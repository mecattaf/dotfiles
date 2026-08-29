---
name: drain
description: Manually distill the exact current root Claude Code or Codex session into the local Markdown journal through the request-scoped NPU utility model. RETIRED 2026-08-29 — that NPU is decommissioned permanently, so this skill now only reports a clean refusal and writes no note. Use only when the user explicitly invokes /drain or $drain, or plainly asks to drain the current session.
---

# Drain the current session

## Status: retired 2026-08-29

Drain's distillation always ran on the request-scoped NPU utility model. That
NPU was decommissioned on both Strix Halo boxes on **2026-08-29**, permanently:
the `utility-model` wrapper is no longer installed on any host, and no
configuration switch brings it back.

So when this skill is invoked now, the command below resolves the exact
session, then refuses at the model seam with one clean line on stderr —

    ai-memory: the NPU utility model was decommissioned 2026-08-29; the
    /drain distillation path is retired — no configuration switch restores it

— and exits 1. Report that refusal verbatim and stop. No journal note is
written, nothing is left half-written, and the hard boundaries below still
hold: in particular, do not reach for a main agent, a cloud model, or a paid
fallback to produce the note the local model can no longer produce. `identity`
and `pickup` are untouched; only distillation is gone.

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
  skill. The user must request every drain.
