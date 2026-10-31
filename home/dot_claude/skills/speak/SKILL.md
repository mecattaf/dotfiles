---
name: speak
description: Toggle spoken answers for this conversation, or read one requested answer aloud, by dropping Markdown into the configured NAS speech intake. Use for /speak or an explicit request to read answers aloud.
---

# Speak

`/speak` or `/speak on` enables spoken final answers in this conversation until
`/speak off`. `/speak once` reads only the requested answer. Keep ordinary written
answers too. Do not enable other conversations or turn progress/tool logs into
speech. Turning off stops new drops; it does not cancel an already queued job.

Resolve `speech_root=$(utility-path speech)` on NAS (or `ssh nas utility-path speech`).
The concrete root is configured privately on the host.

For each answer to read, write its Markdown on the **nas**, using a unique
name for this conversation and turn:

    ${speech_root}/intake/.<unique-turn-name>.md.tmp

Then rename it to:

    ${speech_root}/intake/<unique-turn-name>.md

The final rename submits the answer. Never write directly to the final filename
or resubmit the same turn. From another host, copy the temporary file to the
NAS and rename it there.

Write the answer the user requested; do not silently summarize or add a persona.
Keep it readable aloud. No TTS commands, model calls, voice selection, timestamps,
or scheduling decisions belong in this skill: the speech daemon owns those.

The daemon uses the accepted K2SO reference voice, deterministic Qwen batching,
and Zenbook playback. It follows print's waking hours: 06:00–24:00 in the
NAS's configured timezone, with overnight jobs held for morning.

A submitted file is **queued**, not proof of playback. Only report completion
from `${speech_root}/spoken/<job>/receipt.json`; failures remain under
`${speech_root}/failed/<job>/`. Do not poll unless the user requests delivery status.
