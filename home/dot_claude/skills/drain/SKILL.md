---
name: drain
description: Manually distill the exact current root Claude Code or Codex session into the local Markdown journal through the request-scoped NPU utility model. Use only when the user explicitly invokes /drain or $drain, or plainly asks to drain the current session.
---

# Drain the current session

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
