---
name: pickup
description: Continue from one exactly identified drained Claude Code or Codex session by loading only its bounded reviewed handoff and emitting lineage for the new session. Use when the user invokes /pickup or $pickup with source:session-id.
argument-hint: "<claude-code|codex>:<session-id>"
---

# Pick up one drained handoff

Pass the user's exact `source:session-id` reference as one quoted argument,
replacing the placeholder below:

```bash
python3 "$HOME/.agents/skills/drain/scripts/ai_memory.py" pickup "<source:session-id>"
```

On success, reproduce the command's complete output verbatim in the visible
assistant response before continuing from the handoff. In particular, keep the
`ai-memory:parent` marker intact: a later drain uses it to inherit the
predecessor's two-word group and record lineage.

Read and act from only that returned handoff. Do not locate or read the old raw
trace, guess from filenames, load the old note's other sections, or substitute
a near match. If exact lookup or handoff validation fails, report the failure
clearly. Pickup never writes the journal, invokes the utility model, or runs
Git.
