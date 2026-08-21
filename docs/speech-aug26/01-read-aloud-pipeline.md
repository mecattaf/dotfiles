# The `/speak` reading pipeline

## Goal

The interaction should feel like `/print` in authorship and provenance, but it must not inherit paper’s latency:

> Give the smart agent a document, note, answer, selection, or stdin. It prepares exactly what should be heard. A deterministic local utility begins reading promptly, while an optional explicit polish mode can make bounded delivery choices.

This is not a chat loop and does not require a microphone. It has an immediate playback mode and a durable transformation mode whose output happens to be audio.

## What to preserve from `/print`

The existing print workflow has a strong division of labor:

1. Codex or Claude owns meaning and writes final Markdown.
2. A request-scoped NPU model chooses only from a small validated JSON schema.
3. Deterministic code performs rendering, validation, and output.
4. The job directory retains source, decision, artifact, and a reproducibility receipt.
5. Invalid model output is retried once and then falls back safely.

The TTS version should preserve that shape for durable rendering, but the small model must not sit on the ordinary playback critical path. It should be invoked only for an explicit `--polish`, `--brief`, or complex oral-adaptation request. It must never summarize facts, silently omit paragraphs, or invent content. When invoked, it can decide bounded presentation metadata such as:

- voice profile;
- reading mode (`verbatim`, `spoken-prose`, `briefing`, or `code-aware`);
- pace and pause profile;
- whether headings, URLs, citations, tables, code, and footnotes need an oral rendering;
- chunk boundaries and filename/title.

The smart agent should perform any material rewrite before submitting the job, leaving an inspectable Markdown source.

## Proposed contract

Conceptually, not as a frozen CLI:

```text
file / stdin / agent answer
        │
        ▼
prepared source.md
        │
        ├── optional bounded decision.json (`--polish` only)
        ▼
deterministic oral normalizer
        │
        ├── engine-neutral chunks
        ├── stable logical voice ID
        ▼
TTS adapter → native-rate audio chunks → join / loudness check
        │
        ├── archive only
        ├── play now
        └── mark ready (quiet hours)
```

Useful input forms are a Markdown path, plain-text path, stdin, clipboard/selection, or an already-prepared agent response. The executor should return only when the requested completion condition is true: rendered, queued, or fully played. A fire-and-forget command that reports success before playback completes is not the `/print` analogue.

## Three modes, not one slow path

```text
/speak [file|-]            fast, deterministic, begin on first safe clause
/speak --polish [file|-]   optional utility-model oral rewrite, then speak
/speak --render [file|-]   durable complete artifact + validation + receipt
```

The default should accept text in milliseconds, normalize only what is mechanically safe, and stream it to a warm engine. `--polish` is intentionally slower and visible because it asks another model to reshape material. `--render` waits for the whole artifact, validates it, and is the closest analogue to `/print`.

Completion has three distinct meanings and the caller must select or observe them:

- **accepted:** request and voice resolved;
- **playing:** first audio reached the selected PipeWire route;
- **played:** requested text completed without cancellation.

The slash command itself contributes negligible latency. Cold model load, time to first generated audio, text buffering, and whole-file playback designs are the actual risks.

## Fast path and latency budget

For an already-authored agent answer, do not run a second model. Consume streamed final-answer text, strip only known non-spoken structures, and release a clause when it ends cleanly or reaches a bounded length—roughly 8–20 words is a useful starting window. The TTS daemon stays resident and receives the next clause while the current clause plays.

```text
agent text delta
  → safe-clause accumulator
  → deterministic spoken-text normalizer
  → persistent TTS request/audio clock
  → small PCM jitter queue
  → pw-play/PipeWire
```

Target budgets for the first benchmark, not claims already achieved, are:

| Phase | Warm-path target |
|---|---:|
| slash dispatch and IPC | under 50 ms |
| deterministic normalization | under 30 ms |
| TTS request to first playable PCM | 250–800 ms, engine-dependent |
| cancellation to silence | under 150 ms |
| queued speech ahead of playback | at most one clause |

Qwen C++ first-audio performance on this exact Strix Halo has not yet been measured, so the 250–800 ms range is a promotion target. Cold loading may take seconds; keep the selected conversational engine warm, or use a small fixed-voice fallback for acknowledgements while it starts. Precompute the chosen clone prompt, embedding, or codec tokens so reference analysis is not repeated on every utterance.

## A job should remain auditable

A durable job directory should contain at least:

```text
source.md                 exact text submitted for speech
decision.json             validated bounded choices, when polish was requested
spoken.txt                final normalized text sent to engines
chunks/                   optional native engine outputs
output.wav|flac|opus      joined artifact
synthesis.json            engine, model, voice revision, settings, timings, hashes
played.json               route, start/end, interruption, completion
```

This gives a failed or surprising reading the same debuggability as a print job. It also prevents “which voice/model produced this?” from becoming unknowable after a model update.

## Oral preparation is semantic work

Markdown-to-speech cannot be handled well by one global regex. The agent should explicitly prepare difficult structures:

- A table may become a row-by-row comparison or a short summary, depending on the request.
- A URL normally becomes a link label, but a command or hostname may need spelling.
- A code block may be skipped, described, or read literally.
- Footnote markers and raw citation syntax should not be vocalized accidentally.
- Long lists need grouping and audible transitions.
- Parentheses, slash-heavy prose, emoji, and inline paths need deliberate treatment.

The archive should retain both `source.md` and `spoken.txt` so the transformation is visible. If the user says “verbatim,” the normalizer can expand pronunciation markup but must not semantically condense the source.

## Quiet hours are not print hours

The paper workflow can safely render at night and submit later at 06:05. Audio is different: automatically starting loudspeaker playback hours after the original command would be surprising.

Recommended default policy:

| Situation | Result |
|---|---|
| Daytime, explicit play | Render and play on the selected route |
| Quiet hours, headphones selected | Allow playback if explicitly requested |
| Quiet hours, speakers selected | Render, archive, notify “ready”; do not auto-play later |
| Any time, render-only | Produce artifact without playback |
| Explicit force/scheduled alarm mode | Separate, conspicuous override |

Playback should use stable PipeWire node identities from the existing route mechanism, not the incidental numeric default reported by PortAudio. Changing from INZONE headphones to GS3 speakers should be an explicit policy input.

## Engine boundary

The executor should target a narrow local interface rather than import every TTS implementation into the skill. An OpenAI-compatible subset is a reasonable northbound shape:

```text
POST /v1/audio/speech
  model: logical engine profile
  input: chunk text
  voice: logical voice ID or bounded design instruction
  speed: optional
  response_format: wav/pcm where supported
```

The adapter can translate this to Qwen C++, Chatterbox, OpenMOSS, VibeVoice, or another engine. Engine-specific management and model downloads should not be exposed through the reading command.

Native sample rate matters. The realtime conversation reference repository uses a 16 kHz internal audio bus; that is appropriate for microphone transport but needlessly degrades a high-fidelity reading renderer. `/speak` should synthesize and join at the engine’s native rate, converting only at a final explicitly chosen output boundary.

## Stable voice registry

Callers should use names such as `assistant-main`, `assistant-fast`, or `narrator-experimental`. Each registry revision should record:

- source type: designed, built-in, or reference-enrolled;
- exact design instruction or reference recording;
- reference transcript and language;
- source location, extraction/cleanup recipe, and quality notes;
- content hashes;
- engine/model/quantization compatibility;
- derived artifacts such as `.spk`, `.rvq`, embeddings, or codec tokens;
- listening-test status.

This lets the chosen identity move between engines without changing every agent integration and makes the conditioning source reproducible rather than a forgotten file in Downloads.

## What `pi-voice` teaches

[`S1M0N38/pi-voice`](https://github.com/S1M0N38/pi-voice/tree/10d06bb03542790492752eb3cfe4bf8860c3bde1) is for the Pi coding agent, not Raspberry Pi. It is remarkably close to the desired interaction model:

- `/voice`, a shortcut, a TTS tool, and automatic speech on agent events;
- a clean side-agent session with no tools, extensions, or skills to prepare the last answer for speech;
- an event-specific small model override;
- a persistent Kokoro service;
- serial synthesis and playback queues;
- PipeWire-first `pw-play` fallback behavior.

Those are good ideas to reuse. It should not be adopted unchanged: its clean side-agent makes every automatic utterance slower, it has a bespoke `/tts` API, fixed CPU Kokoro voices, whole-WAV playback, regex-only Markdown cleanup, no cancellation, no quiet-hours policy, no durable receipt, and its tool can return before playback completes. Its detached PID service also belongs in a declared user service on this machine.

The preferred Pi integration is smaller: an extension exposes `/speak`, logical voice selection, and playback events, while a shared external speech controller owns synthesis and playback. Automatic speech should attach to authoritative final-answer events. A side model remains an opt-in polish mode, not the default.

## Failure and cancellation semantics

- A failed chunk should not silently yield a truncated “successful” artifact.
- Joined output should be checked for duration, decodability, channel/sample-rate consistency, clipping, and unexpected silence.
- Playback cancellation should stop the player and mark the receipt as interrupted, while retaining rendered audio.
- A superseding request may cancel queued playback without deleting its source or synthesis receipt.
- Model and voice resolution must occur before synthesis starts so a job cannot switch voice revision midway.

## Scope decision

Build `/speak` before integrating wake words or full duplex. It exercises the voice, engine API, chunker, routing, quiet-hours policy, and voice registry without taking on microphone privacy or realtime cancellation. Those same stable engine adapters can later serve the conversation system.
