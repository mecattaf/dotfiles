---
name: handoff
description: Author a bounded, reviewable continuation handoff in the current Claude Code or Codex session without saving or draining it. Use when the user explicitly invokes /handoff or $handoff, or asks for a continuation handoff.
argument-hint: "[what the next session should emphasize]"
---

# Author a continuation handoff

First obtain the exact current source/session identity:

```bash
python3 "$HOME/.agents/skills/drain/scripts/ai_memory.py" identity
```

Use the returned values to produce this exact visible structure:

```markdown
<!-- ai-memory:handoff {"version":1,"source":"<source>","session_id":"<session-id>"} -->
## Handoff

<bounded handoff>
<!-- /ai-memory:handoff -->
```

The body is authored by the active capable agent, guided by the direction the
user supplied with this invocation. Keep it under 700 words and low-prose.
Prefer short `###` subsections and bullets covering only what a fresh agent
needs:

- objective and current state;
- user-settled decisions and rejected directions;
- constraints that must survive;
- durable artifacts and verification already completed;
- unresolved gates and concrete next actions.

Be precise about incomplete work. Do not include hidden reasoning, raw tool
output, transcript excerpts, or secrets. Do not place another `##` heading or
an AI-memory marker inside the body.

This skill only returns text for the user to review. It must never run drain,
write the journal, invoke the utility model, run Git, or claim the session has
been saved. The user corrects the block if needed and invokes drain separately.
