# Local speech on Strix Halo — August 2026 investigation

Status: investigation and architecture only. No speech runtime, service, model, or firewall rule was enabled while preparing these notes.

This is the complete research suite, not a report constrained to wake words and voice cloning. It covers the `/speak` reading workflow, candidate engines, Jarvis and K-2SO voice construction, the agent harness, realtime speech-to-speech, an actual Strix Halo wake-word design, phone access, translation, and a staged final stack.

## The short version

There are two different products hiding inside “local speech,” and they should stay separate:

1. **`/speak`: prepared text → immediate or durable audio.** Codex or Claude writes the complete spoken text. The default fast path performs deterministic oral normalization and starts a warm streaming TTS engine on the first safe clause. A request-scoped utility model is optional for explicit `--polish` work; it must not gate normal playback. A render mode retains the complete source, audio, and receipt like `/print`.
2. **`speech-agent`: microphone → turn-taking conversation.** This is a long-lived state machine involving wake detection, ASR, endpointing, cancellation, the agent, TTS, echo control, and possibly a phone/WebRTC client. It has different latency and safety requirements from document reading.

The models can share stable local APIs and a voice registry. They should not be forced into one Python environment or kept resident merely because they fit on disk.

## Recommended direction

- Keep **Parakeet/Voxtype** as the live English ASR baseline. It is already resident, genuinely streaming, and declaratively integrated.
- Evaluate **Qwen3-TTS through both C++ implementations** first for the primary assistant voice. It offers the most interesting combination of voice design, reference cloning, quantization, Vulkan, streaming, and an OpenAI-compatible server.
- Evaluate **Chatterbox, OpenMOSS, and OmniVoice** as identity/cloning challengers; use **VibeVoice** for long-form and multi-speaker work; retain **Kokoro or Supertonic** as the small, fast control.
- Treat **ACE-Step** as a separate music-generation capability, not a TTS backend.
- Put a small **`speech-loop` media controller** between capture/playback and the agent. Use **Pi RPC as the first conversational brain adapter**; Pi supplies sessions, tools, streamed text, steering, and abort, while the controller owns the microphone, turn state, clause buffer, TTS, and audio clock.
- Borrow the Hugging Face `speech-to-speech` repository’s turn/revision and cancellation semantics, OpenClaw’s agent-proxy boundary, and Hermes’s clause-streaming latency work—not their complete platforms.
- Implement awake-only summoning with an **OpenWakeWord `hey_jarvis` ONNX detector on CPU**, fed from the pinned PipeWire microphone. The two-stage first release is `wake → chime → Voxtype capture → agent`; it reuses the already-resident Parakeet model. One-breath commands require a later raw-PCM ingress into the resident ASR service.
- For phone access, first test a **foreground, half-duplex app over the existing Tailscale mesh**. Lemonade Mobile is a useful disposable client even if Lemonade never becomes the server. Move to WebRTC only if interruption and full duplex prove important.
- Do not enable the whole Lemonade control plane merely to obtain `/v1/audio/speech`. Its API is useful; adoption of the product is a separate decision.
- Build two stable local voice profiles: a Jarvis-style designed voice and a literal, permanently local K-2SO/Alan Tudyk clone. The available two-plus minutes of clean K-2SO material are enough for a reference bank and a held-out test set; individual engines should still receive their preferred short conditioning excerpts rather than one blind two-minute concatenation.

## Documents

- [Single-file complete report](speech-aug26-report.md) — mechanically assembled from the chapters below for reading and printing
- [01 — The `/speak` reading pipeline](01-read-aloud-pipeline.md)
- [02 — Engines, models, and the Strix Halo fit](02-engine-and-model-evaluation.md)
- [03 — Voice identity: Jarvis, K-2SO, design, and cloning](03-voice-identity.md)
- [04 — End-to-end speech-to-speech](04-realtime-speech-to-speech.md)
- [05 — Wake-word implementation on Strix Halo](05-alexa-style-summoning.md)
- [06 — Calling the local agent from a phone](06-phone-access.md)
- [07 — Bounded evaluation plan](07-evaluation-plan.md)
- [08 — Recommended final stack and component ownership](08-final-stack.md)

## Existing local ground truth

The proposal is based on the current dotfiles rather than a generic Linux setup:

- [`home/voxtype.nix`](../../home/voxtype.nix) already declares streaming `parakeet-unified-en-0.6b` through ONNX/MIGraphX, with a 0.32-second chunk and cached left/right context.
- [`home/dot_claude/skills/print/SKILL.md`](../../home/dot_claude/skills/print/SKILL.md) and its scripts establish the “smart author → bounded utility decision → deterministic executor → archived receipt” pattern.
- [`home/paper.nix`](../../home/paper.nix) establishes quiet-hours behavior for physical output.
- [`home/dot_config/niri/scripts/audio-route`](../../home/dot_config/niri/scripts/audio-route) and [`modules/common.nix`](../../modules/common.nix) establish explicit PipeWire routes and Tailscale as the private access plane.
- [`modules/strix.nix`](../../modules/strix.nix) deliberately leaves Lemonade disabled and keeps NPU, GPU, and model ownership separated.

The requested upstream repository was cloned, but not installed or run, at `/home/tom/Downloads/speech-to-speech`. It was clean at commit [`41536471e074723543ba6fc023319a96544f4303`](https://github.com/huggingface/speech-to-speech/tree/41536471e074723543ba6fc023319a96544f4303) when reviewed.

Fast-moving upstream HEADs observed on 2026-08-13 were: OpenClaw `8e0f464a`, Hermes Agent `787f42cc`, Lemonade Mobile `9cc69587`, `khimaros/qwen3-tts.cpp` `0c8b2ba0`, `ServeurpersoCom/qwentts.cpp` `a8a7716b`, `rhasspy/pyopen-wakeword` `6bc5c5f5`, and `sherpa-onnx` `3e409338`. The documents describe those snapshots; re-check before implementation.

## Architectural boundary

```text
prepared text ──> /speak fast/render ──────────────┐
                                                   ▼
desktop/phone ──> wake/transport ──> speech-loop ──> TTS adapter ──> audio
                       │                │               │
                       ▼                ▼               ▼
                Voxtype/Parakeet    Pi RPC first   voice registry
```

The northbound contracts should be stable and engine-neutral. A voice name such as `assistant-main` should resolve through a registry rather than leak an engine-specific speaker file into every caller.

## Non-goals for this scope

- No package selection is final.
- No film audio was extracted, transcribed, or used for cloning.
- No model was downloaded or loaded.
- No always-on microphone service was started.
- No phone, SIP, PSTN, WebRTC, or public endpoint was exposed.
- The K-2SO voice is scoped as permanently local-only, as specified.

Research snapshot: 2026-08-13.


---

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


---

# Engines, models, and the Strix Halo fit

## Existing baseline

The machine already has an unusually good speech foundation:

- **Live English ASR:** Voxtype owns `parakeet-unified-en-0.6b` through ONNX/MIGraphX with cached streaming context. Do not replace it merely to make a demo repository self-contained.
- **Long-form ASR:** VibeVoice ASR is already represented in the local model inventory and call-diarization work.
- **Long-form TTS weights:** the current `vibevoice-large-bf16` artifact is the same [`aoi-ot/VibeVoice-Large`](https://huggingface.co/aoi-ot/VibeVoice-Large) model used by Kyuz0’s Strix Halo toolbox.
- **NPU utility inference:** FastFlowLM is request-scoped and separately owned. Tiny wake models do not automatically benefit from being moved onto the NPU.
- **Unified memory:** it makes large models possible, but is not a reason to keep every ASR, TTS, and music model resident.

The existing weight sizes also correct the intuition that everything is “quite small”: Parakeet is about 2.5 GB locally, VibeVoice ASR about 17.3 GB, and VibeVoice Large TTS about 18.7 GB. Several engines can coexist on disk; simultaneous residency and bandwidth contention still need measurement.

## Candidate roles

| Candidate | Best question it answers | Voice control | Strix route | Current judgment |
|---|---|---|---|---|
| Qwen3-TTS 0.6B/1.7B | Can one engine provide designed identity, cloning, and low-latency speech? | Built-ins, reference cloning, 1.7B voice design | C++ Vulkan implementations; Python/ROCm comparison | First evaluation priority |
| Chatterbox | How good is short-reference identity enrollment? | Zero-shot reference; expressive controls vary by model | ROCm/PyTorch, community hybrid, `audio.cpp` | Strong cloning challenger |
| OpenMOSS/MOSS-VoiceGen | Can cloning and free-text voice design share one API? | Reference clone and text design | standalone GGML C++ Vulkan/ROCm or Lemonade adapter | High-value challenger, fast-moving |
| OmniVoice | Can a compact model deliver realtime cloning quality? | Reference cloning | emerging `audio.cpp` path | Promising; community results need reproduction |
| VibeVoice Large | How well does long-form/multi-speaker synthesis hold together? | Presets and custom WAV conditioning | Kyuz0 ROCm recipe; local weights exist | Long-form specialist, not first low-latency daemon |
| Kokoro | What is the small fixed-voice latency/control floor? | Fixed voices | CPU/ONNX and multiple servers | Excellent baseline, not identity target |
| Supertonic | What does a very small multilingual ONNX engine achieve? | Fixed/designed profiles; exact local builder/API needs checking | ONNX | Fast baseline candidate |
| `audio.cpp` | Can one C++ harness compare many audio architectures consistently? | Depends on model | Vulkan mature, HIP evolving | Evaluation harness; avoid premature monolith |
| ACE-Step | Can the box generate songs/music? | Music prompting/conditioning | Strix community recipes | Separate product lane, not TTS |

## Qwen3-TTS

The official [`QwenLM/Qwen3-TTS`](https://github.com/QwenLM/Qwen3-TTS) family is the most direct match for the intended assistant:

- Base models support reference voice cloning.
- The 1.7B VoiceDesign model creates a voice from an attribute instruction.
- The documented design-then-clone workflow can create an original seed voice and then reuse it consistently.
- 0.6B and 1.7B sizes permit a quality/latency comparison rather than one all-or-nothing deployment.

Two C++ efforts are worth testing independently rather than treating “Qwen C++” as one result:

### `ServeurpersoCom/qwentts.cpp`

[`qwentts.cpp`](https://github.com/ServeurpersoCom/qwentts.cpp) currently exposes named speakers, reference cloning, voice design, streaming, Q8/Q4 quantization, Vulkan builds, a C ABI, and an OpenAI-compatible speech server. Pre-encoded speaker/codec artifacts make it attractive for a real voice registry.

### `khimaros/qwen3-tts.cpp`

[`qwen3-tts.cpp`](https://github.com/khimaros/qwen3-tts.cpp) is a narrower upstream-GGML implementation with a single CMake/Vulkan path, CLI/server, streaming state, Q8/F16, reference conditioning, and 1.7B voice design. Its current server exposes OpenAI-compatible `/v1/audio/speech` and `/v1/audio/voices`, multipart voice enrollment, and genuinely chunked PCM vocoder output while the transformer is still generating. The Strix Halo community speed report is useful but remains an anecdote until reproduced with identical text, voice, output settings, and first-audio measurement.

The screenshot comparison supplied in this investigation captures a real tradeoff: `ServeurpersoCom` has the broader public API and quantization/registry surface; `khimaros` has a simpler build and integrated HTTP server. The benchmark should evaluate both, not select by stars.

For `/speak` and conversation, first-audio streaming and reusable enrollment artifacts matter more than total-file time alone. A server that returns one complete WAV can sound slow even when its realtime factor is excellent.

## Chatterbox

[`resemble-ai/chatterbox`](https://github.com/resemble-ai/chatterbox) offers compact variants and short-reference zero-shot cloning. Its role here is to **enroll a controlled reference recording**, then measure identity, stability, prosody, and Strix acceleration. A clean 10–30 second recording is much more useful than hours of dialogue mixed with music and effects.

Candidate execution paths include a dedicated ROCm/PyTorch environment, an AMD community hybrid server, and [`audio.cpp`](https://github.com/0xShug0/audio.cpp). None should be merged into the global Python environment.

## OpenMOSS and Lemonade

The official [`OpenMOSS/MOSS-TTS`](https://github.com/OpenMOSS/MOSS-TTS) family includes speech cloning and voice design and is developing rapidly. [`pwilkin/openmoss`](https://github.com/pwilkin/openmoss) is the relevant standalone GGML C++ implementation with Vulkan/ROCm and an OpenAI-compatible speech endpoint.

Lemonade’s current `/v1/audio/speech` contract is interesting because it presents:

- Kokoro fixed voices and PCM streaming;
- OpenMOSS cloning through `reference_wav_b64`;
- MOSS VoiceGen free-text voice/style instructions;
- the familiar OpenAI request shape.

But [`lemonade-sdk/lemonade`](https://github.com/lemonade-sdk/lemonade) is a broad model/runtime control plane, not merely a speech adapter. The dotfiles deliberately leave it disabled, and the machine already has carefully separated llama-swap, FastFlowLM, Voxtype, and model ownership. Lemonade Mobile’s useful phone loop needs only three OpenAI-shaped routes and does not force server adoption. The correct conclusion is:

> Preserve Lemonade’s useful API shape and test its speech backend in a bounded environment; do not adopt the whole platform until it wins on lifecycle, reproducibility, security, and coexistence.

“AMD sponsored/community maintained” is more accurate than treating it as an official AMD product boundary. If ever promoted, it should be pinned and Nix-owned, with no silent runtime model downloads and no authority over unrelated LLMs.

## VibeVoice and Kyuz0

[`kyuz0/amd-strix-halo-voice-toolbox`](https://github.com/kyuz0/amd-strix-halo-voice-toolbox) is valuable because it proves a specific Strix Halo path for the exact VibeVoice Large artifact already present locally. It uses Fedora Toolbox, Python 3.13, gfx1151 ROCm/TheRock PyTorch, ROCm flash attention, Kyuz0’s VibeVoice fork, and compatibility workarounds for a numba/LLVM collision. It also accepts custom WAV voice conditioning.

That makes the repository an excellent **executable bill of materials and patch oracle**. It is not a reason to replace the Nix architecture with Toolbox. The dependencies, pins, environment shims, and patches should be translated into an isolated Nix-owned runtime if VibeVoice wins its long-form tests.

Kyuz0’s broader Strix Halo work is worth continuing to monitor because it is close to this hardware and frequently exposes the exact gfx1151 packaging gap. One local distinction must remain: do not copy Fedora advice to disable IOMMU. This machine’s XDNA/NPU path relies on translated IOMMU mode.

> **Superseded 2026-08-29: the NPU is decommissioned and `amd_iommu=off` is now the fleet setting; this warning is void.** The XDNA/NPU path it protected no longer exists on either Strix Halo twin, and FastFlowLM is retired with archive receipts (see `lib/local-models.nix`). The sentence above is kept as the documented reason it was ever written.

## ASR and translation

Parakeet and VibeVoice ASR have different jobs:

- **Parakeet/Voxtype:** low-latency live English command and dictation path.
- **VibeVoice ASR:** long recordings, diarization, and batch work where its larger footprint can be justified.

The AMD [`Real-Time Speech-to-Speech Translation`](https://developer.amd.com/playbooks/speech2speech-translation/) playbook is current enough to be useful as a gfx1151/ROCm environment reference, but its demo is not actually a conversational realtime stack. It loads [`facebook/seamless-m4t-v2-large`](https://huggingface.co/facebook/seamless-m4t-v2-large), consumes a complete WAV, calls `generate`, and writes another WAV. It has no streaming session, interruption, turn state, or speaker-identity preservation.

SeamlessM4T therefore belongs as an optional **translation bridge** after capture, not as the core agent architecture.

## Packaging doctrine

- One owner for every model artifact and cache path.
- Pinned revisions and hashes; no model download during service startup.
- Per-engine Nix environment or service, not one Python environment containing all audio projects.
- Loopback-only inference endpoints by default.
- Lazy/on-demand residency for large specialists.
- Stable northbound speech API and logical voice IDs.
- Benchmarks record exact commit, model hash, quantization, driver/runtime, text corpus, voice reference, native sample rate, and route.

“Stacking” should mean composing services and keeping alternatives available, not keeping 50+ GB of specialists active at the same time.


---

# Voice identity: Jarvis and K-2SO

## Two useful target profiles

The local voice registry should eventually expose two distinct voices:

1. **Jarvis-style designed voice:** composed British machine intelligence, built through text-described voice design and tuned for comfortable long-form reading.
2. **K-2SO / Alan Tudyk clone:** a literal resemblance target conditioned from the cleanest recoverable K-2SO dialogue, optimized for the dry, blunt performance heard in *Rogue One*.

Both can use the same `/speak` and realtime TTS interfaces. They differ in how the voice source is constructed and evaluated.

## What `alexberardi/jarvis` actually contains

[`alexberardi/jarvis`](https://github.com/alexberardi/jarvis/tree/90ae07760f7c1e72061db4d0273047d9418d70f2) is a serious whole-assistant platform, not a reusable celebrity-voice model. The current TTS service uses:

- Piper `en_GB-alan-low`, a small 16 kHz generic British male voice; or
- Kokoro-82M, defaulting to the 24 kHz British male `bm_george` voice.

Neither is Paul Bettany/JARVIS cloning, reference-audio cloning, or text-described voice design. `jarvis-tts` exposes `/speak` and `/speak/stream`, not OpenAI `/v1/audio/speech`; voice/provider settings are global rather than per request. Its device settings cover CPU, CUDA, and MPS, while its container GPU path is NVIDIA-specific. It does not establish Strix Halo acceleration.

The project’s most reusable material lies elsewhere.

### Current summoning/audio path

One long-lived `AudioBus` owns the PyAudio capture stream, retains ring history, and fans 80 ms frames into named bounded/drop-oldest queues. ReSpeaker input arrives at 48 kHz and is resampled to OpenWakeWord’s 16 kHz frames. The default `hey_jarvis` model uses ONNX Runtime with threshold and debounce logic.

When accepted, the node:

1. pauses the ordinary wake consumer and ducks media;
2. snapshots about two seconds of wake audio for speaker matching;
3. plays a cached acknowledgement;
4. prewarms LLM/tool state while the command is still being spoken;
5. records until adaptive RMS silence;
6. sends command-only audio to Whisper and wake-plus-command audio to its speaker model;
7. consumes streamed PCM from the command center.

Closing the HTTP response cancels upstream generation and playback. Follow-up supports up to five turns with decreasing timeouts. Its “barge-in” is much narrower than full duplex: the user says `hey_jarvis` during TTS, playback stops, and the system returns to wake mode without retaining the replacement command. There is no acoustic echo cancellation.

Primary sources: [audio bus](https://github.com/alexberardi/jarvis-node-setup/blob/07aab710d9f233f19bf40e40e2f98bec1e8f833f/core/audio_bus.py), [listener](https://github.com/alexberardi/jarvis-node-setup/blob/07aab710d9f233f19bf40e40e2f98bec1e8f833f/scripts/voice_listener.py), and [wake loop](https://github.com/alexberardi/jarvis-node-setup/blob/07aab710d9f233f19bf40e40e2f98bec1e8f833f/core/wake_loop.py).

### Latency ideas worth borrowing

- Pre-rendered wake acknowledgement clips avoid waiting for live TTS; the author measured roughly 30 ms local playback in place of roughly 880 ms network synthesis.
- Short processing acknowledgements can mask a genuinely unavoidable wait.
- Model and tool warmup overlaps the user’s recording time.
- TTS streams sentence-by-sentence PCM with explicit format metadata.
- Capture and playback queues are bounded.
- Cancellation closes the upstream stream rather than merely muting stale audio.

Those patterns fit a small NixOS speech supervisor. The 13-service/~17-container platform, Pi installer, databases, observability, dynamic package system, global voice configuration, and Home Assistant control plane do not.

### Demo mismatch

At reviewed HEAD, the repository contains a commented TODO asking for a real 20–30 second wake-to-answer demo; no such demo is linked. The creator’s current [M4 Mac Mini installation video](https://www.youtube.com/watch?v=S7XTyQR6f30) is a silent installer/terminal recording. It demonstrates installation on Apple Metal, not wake detection, ASR/TTS quality, interruption, latency, or AMD behavior. The headline latency result is from an RTX 3080 Ti. Neither should be treated as Strix Halo evidence.

## What produces the K-2SO sound

Primary production interviews show Alan Tudyk trying multiple accents, choosing English/Imperial diction, and deliberately forming words as if he were a machine while performing K-2SO in motion capture. See [StarWars.com’s interview](https://www.starwars.com/news/andor-season-2-interview-alan-tudyk-k2so), [WIRED’s performance demonstration](https://www.wired.com/video/watch/how-alan-tudyk-became-rogue-one-s-k-2so), and [ILM’s production discussion](https://www.ilm.com/hal-hickel-discusses-rogue-one/).

No credible production source found in this review documents a signature heavy vocoder, pitch-shift, or formant-conversion chain. The recognizable result appears to be driven primarily by:

- precise British/Imperial diction;
- deliberate word formation and clipped consonants;
- low breathiness and even cadence;
- restrained emotional range;
- blunt literal delivery and dry humor;
- occasional childlike curiosity beneath machine confidence.

This is an inference from the production record, not proof that no light studio processing occurred. The theatrical signal is still edited, mixed, EQ’d, compressed, reverberated, and sometimes ADR’d.

## The available two-minute source is enough

The center channel of a surround mix is not an isolated dialogue stem. It may contain score, foley, other speakers, room response, scene reverb, dynamic EQ, compression, and effects. Separation can reduce those contaminants but can add warble, missing consonants, and phase artifacts of its own.

There are more than two minutes of genuinely clean K-2SO audio available locally. That changes the source-preparation problem substantially: the corpus is large enough to select multiple pristine references, cover varied phonemes and deliveries, and hold material back for honest evaluation.

It does **not** mean every engine should receive one two-minute concatenation. Zero-shot conditioners are usually optimized for short references and may truncate, average incompatible deliveries, or copy room tone when overfed. For these engines, a carefully chosen short excerpt can still outperform a long undifferentiated prompt. The full set is valuable because it provides a pool from which to select:

- acoustically dry close dialogue;
- no overlapping speaker;
- little or no score and machinery;
- stable loudness;
- complete phrases with accurate transcripts;
- complementary vowels, consonants, pitch, and pacing.

Do not simply concatenate every extracted line and send it to each engine. Build several purpose-specific references.

## Proposed source preparation pipeline

```text
local multichannel movie audio
  → preserve original channels and timestamps
  → subtitle/manual K-2SO line index
  → candidate center-channel segments
  → optional dialogue/source separation variants
  → trim overlaps, fades, loudness normalization
  → exact per-segment transcript
  → objective + listening quality scores
  → reference banks: 3 s / 8–10 s / 20–30 s / clean corpus
```

### 1. Build a timestamped line inventory

Start with subtitle timings or a local transcript, then correct every K-2SO boundary by ear. Retain scene, timestamp, spoken text, overlapping characters, score/foley level, reverberation, and delivery style. Automated speaker diarization can propose segments, but manual identity and transcript correction should be authoritative.

### 2. Generate several isolation candidates

For each useful line, compare:

- raw center channel;
- center-minus-correlated-left/right variants where appropriate;
- a dialogue/source-separation model output;
- a lightly denoised/de-reverberated version;
- the unprocessed segment as a control.

Do not aggressively clean by default. A little residual room sound is usually less damaging than metallic separation artifacts or erased high-frequency consonants. Archive every transformation and never overwrite the original segment.

### 3. Normalize conservatively

- Convert to mono only after channel comparison.
- Retain a high-quality lossless working rate; resample separately for each engine.
- Remove only leading/trailing material, with short fades that do not cut plosives or breaths.
- Avoid peak normalization per micro-clip, which creates inconsistent apparent distance.
- Use one corpus-level loudness target and reject clipped lines.
- Do not splice inside words or construct impossible cadence.

### 4. Transcribe exactly

Qwen’s strongest cloning path uses both `ref_audio` and the exact `ref_text`. Film subtitles often paraphrase or omit hesitations, so Parakeet/VibeVoice ASR can provide a draft but the final transcript must be manually aligned to the audible words. Preserve contractions, fillers, and meaningful punctuation that affect phrasing.

### 5. Rank reference quality

A small scoring manifest should combine:

- speech-to-background ratio;
- overlap probability;
- reverb/de-reverb severity;
- separation-artifact score;
- clipping and silence;
- transcript confidence;
- phoneme coverage;
- human listening grade;
- delivery match to the desired dry K-2SO persona.

The winning reference bank should include at least:

- **3-second pristine:** Qwen advertised minimum test;
- **8–10-second pristine:** shared zero-shot comparison across engines;
- **20–30-second diverse:** test whether longer context improves identity;
- **60- and 120-second variants:** duration-sweep inputs only for engines that actually accept long conditioning;
- **clean segmented corpus:** available for adaptation/fine-tuning experiments, not assumed necessary;
- **20–30-second held-out set:** never used for conditioning, reserved for blind identity and transcription tests.

## What each engine wants

| Engine | Reference mechanism | Best first K-2SO test |
|---|---|---|
| [Qwen3-TTS Base](https://github.com/QwenLM/Qwen3-TTS) | Three-second zero-shot is advertised; highest-fidelity path takes reference audio plus exact transcript; x-vector-only mode omits text at some quality cost | Compare 3 s, 6 s, 8–10 s, and 20–30 s with exact text; precompute the winning reusable clone prompt or C++ speaker/codec artifact |
| [Chatterbox](https://github.com/resemble-ai/chatterbox) | Official example uses an approximately 10-second reference and no transcript | Use the cleanest continuous 8–10 s phrase; test sensitivity to residual score/reverb |
| [MOSS-TTS](https://github.com/OpenMOSS/MOSS-TTS/blob/main/docs/moss_tts_model_card.md) | Short-reference zero-shot; simple mode needs no transcript; continuation mode has prefix-text rules | Start with the shared 8–10 s reference, then compare the 20–30 s bank if identity is weak |
| Kyuz0 VibeVoice Large path | Community Strix fork accepts custom WAV conditioning for the exact local VibeVoice Large artifact | Evaluate for long-form identity consistency after the shorter engines; record the exact fork behavior |
| Microsoft VibeVoice Realtime 0.5B | Current upstream realtime model uses precomputed voices and removed new acoustic enrollment | Not a K-2SO clone route; use only as a fixed-voice latency comparison |
| community VibeVoice 1.5B implementations | Some claim short raw-WAV cloning | Treat as a separate reproducibility test, not equivalent to the existing Large/Kyuz0 path |

## Fine-tuning is not the first move

Qwen, Chatterbox, and MOSS are designed to reveal voice-cloning quality from seconds of audio. Fine-tuning on all recovered lines adds several new failure modes:

- learning movie mix/reverb as part of the voice;
- overfitting a small set of phrases and emotions;
- degrading pronunciation outside the corpus;
- losing a clean baseline for comparing engines;
- much larger packaging and reproducibility burden.

First determine whether in-context conditioning is sufficient. Only consider adaptation if a clean reference produces the right accent/prosody but consistently misses timbre or long-form identity. If adaptation is tested, train from individually scored dry segments, keep the held-out 20–30 seconds untouched, and compare against the same zero-shot reference.

## Duration sweep for this corpus

Run `3 / 6 / 10 / 20 / 30 / 60 / 120` second variants only where the engine accepts them. Do not compare durations made from different acoustic material: construct a nested high-quality sequence wherever possible, then a separate diversity-optimized sequence. Score identity, pronunciation, cadence, copied ambience, and first-audio cost independently.

For the likely realtime winner, store its enrolled representation in the voice registry—Qwen reusable clone prompt, `.spk`/`.rvq`, embedding, or codec tokens—so `/speak` and conversation requests do not re-analyze two minutes of audio. Keep the full corpus for offline experimentation and re-enrollment, not per-request conditioning.

## Jarvis voice-design route

Jarvis is the complementary experiment because it needs no movie-source recovery. Qwen VoiceDesign or MOSS-VoiceGenerator can generate candidates from a direct brief:

> Composed low-mid British male machine intelligence; precise articulation; measured pace; restrained confidence; understated warmth and dry wit; smooth long-form narration; authoritative without theatrical exaggeration.

Generate several candidates, select by blind listening, render a clean phonetically varied seed, and enroll that seed into Qwen Base/Chatterbox/MOSS just as with K-2SO. This separates **voice generation** from **voice consistency**: the design model invents the timbre, while the cloning model makes it reusable.

## Post-processing experiment

Since no signature K-2SO vocoder chain was found, begin with the dry cloned output. Then compare only small reversible treatments:

- very gentle presence/low-mid EQ;
- light compression for even machine cadence;
- subtle saturation;
- an extremely low wet mix of short metallic doubling or comms coloration.

Keep processed and dry output separate. If the processed version wins only on short clips but becomes fatiguing over ten minutes, the voice registry should use different `assistant` and `narrator` playback profiles rather than baking the effect into the clone.

## Technical acceptance criteria

- recognizable K-2SO identity in blind A/B without revealing the engine;
- clean intelligibility on unseen technical prose;
- stable English accent and timbre for ten minutes;
- no learned score, reverb, or metallic separation residue during silence and fricatives;
- consistent loudness and pace across chunks;
- repeatable encoding from the archived reference bank;
- acceptable first-audio latency for conversation and a higher-fidelity mode for `/speak`;
- graceful pronunciation of paths, acronyms, French names, dates, and numbers.

The decisive comparison is not “all movie audio versus no movie audio.” It is which carefully prepared reference duration and cleanup variant gives each engine the strongest identity without importing the film mix.


---

# End-to-end speech-to-speech

## What “speech-to-speech” means here

For a local agent, the useful first architecture is a cascade:

```text
microphone
  → wake / VAD / endpointing
  → streaming ASR
  → agent + tools
  → incremental response text
  → streaming TTS
  → speaker or phone
```

It is still an end-to-end spoken interaction even though the middle has inspectable text. A native audio-to-audio foundation model is not required, and initially would make tool calls, transcripts, policy checks, cancellation, and independent model replacement harder.

The key design target is not merely low model latency. It is **correct turn ownership**: the user can pause, continue, interrupt, correct, or cancel without hearing stale audio from an obsolete agent response.

## The harness still matters

Yes: ASR and TTS do not replace the agent harness. The harness owns the durable conversation, tool permissions, context, streaming response events, and cancellation semantics. A separate media controller owns physical time—what the microphone is accepting, what text is safe to speak, how much audio is buffered, and what the user actually heard.

The clean boundary is:

```text
speech-loop (media/session edge)           agent harness
  wake, capture, VAD, ASR final   ───────> prompt
  barge-in / correction           ───────> abort | steer | follow-up
  clause buffer + TTS             <─────── assistant text deltas
  heard-text ledger               <─────── final authoritative message
```

Pi is a strong first harness for this machine. [`pi --mode rpc`](https://pi.dev/docs/latest/rpc) exposes a strict JSONL protocol with persistent sessions, `prompt`, `steer`, `follow_up`, `abort`, streamed `message_update` deltas, authoritative `message_end`, tool lifecycle events, and `agent_settled`. That is enough to build the voice controller without teaching Pi how to open PipeWire or load TTS models.

Recommended Pi behavior:

1. Send only an authoritative final ASR transcript as `prompt`.
2. While Pi works, expose tool events visually and optionally play deterministic progress cues; never synthesize thinking, tool JSON, or raw terminal output automatically.
3. Accumulate assistant text deltas into safe clauses. Send the first complete clause to a persistent TTS connection while Pi continues generating.
4. On barge-in, silence playback immediately, then choose `abort`, `steer`, or `follow_up` according to the utterance and current run state.
5. Reconcile against the final `message_end` object and retain a ledger of exactly which prefix was played.

A small Pi extension can provide `/speak`, settings, and `speech:*` events. The audio controller should remain an external user service so Codex, Claude Code, Pi, a desktop wake service, and a phone gateway can all use the same renderer.

## What OpenClaw and Hermes prove

The current OpenClaw and Hermes implementations answer the question “has a cascaded voice agent already been attempted?” emphatically yes.

### OpenClaw: realtime front end, smart-agent consult

OpenClaw’s [Talk mode](https://github.com/openclaw/openclaw/blob/main/docs/nodes/talk.md) supports a native `listen → transcript → active Gateway session → response → TTS` loop and realtime WebRTC/WebSocket variants. Finalized voice turns are appended to the same active agent session as typed turns. Its strongest architecture is `agent-proxy`: the realtime voice layer owns turn timing, interruption, and playback, but delegates substantive work through the normal agent/tool policy. Spoken input during a run can be classified as status, cancel, steer, or follow-up.

The Discord voice implementation makes this split explicit: the voice front end hides the agent’s own TTS tool because playback has one owner; exact consult answers queue in order rather than replacing each other mid-sentence; the voice channel can point at an existing text session. See OpenClaw’s [Discord voice modes](https://github.com/openclaw/openclaw/blob/main/docs/channels/discord.md).

This is the conceptual model to borrow. Installing the complete OpenClaw Gateway is not necessary merely to obtain the boundary.

### Hermes: the best current cascade latency reference

Hermes `0.20` runs the same voice pipeline across CLI, TUI, and desktop. Its [voice mode](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/voice-mode.md) feeds response text live into one per-reply TTS WebSocket while the model is still generating, maintains one audio clock, and supports speech interruption during both thinking and playback. Clause-by-clause synthesis can run ahead while the current clause plays. Its OpenAI-compatible TTS base URL and forwarded voice instructions make a local Qwen server a natural backend.

Hermes also ships an actual wake service: local openWakeWord, open-vocabulary sherpa, or Porcupine; it yields the microphone to the normal voice pipeline on acceptance. That validates the same component split proposed here. Its noise-floor/energy barge-in is useful evidence, but without documented speaker-reference AEC it should not be assumed robust in this room.

### Smaller OpenClaw variants

Most variants stop at voice notes or batch speech:

- PicoClaw can call an OpenAI-compatible `/audio/speech` endpoint, but does not establish a full realtime controller.
- NanoClaw documents Whisper-style transcription rather than a complete TTS/turn loop.
- IronClaw currently marks voice call/Talk/STT/TTS as missing.
- [`openclaw-assistant` / WakeHermesClaw](https://github.com/yuga-hashimoto/openclaw-assistant) is a noteworthy Android client: on-device Vosk wake phrases, partial STT, multiple TTS providers, continuous conversation, and OpenClaw/Hermes HTTP targets. It is a client option, not the Strix media controller.

The general lesson is that an OpenAI-shaped TTS API is common; robust turn ownership, interruption, and audio bookkeeping are the scarce parts.

## What the Hugging Face repository contributes

The requested [`huggingface/speech-to-speech`](https://github.com/huggingface/speech-to-speech/tree/41536471e074723543ba6fc023319a96544f4303) checkout is at `/home/tom/Downloads/speech-to-speech`, clean at commit `41536471e074723543ba6fc023319a96544f4303` when reviewed. It was cloned for analysis only; nothing was installed or run.

It is best understood as a **conversation-control-plane reference**, not a production runtime for this machine. Internally it constructs long-lived threaded handlers connected by queues:

- VAD and turn decision;
- STT;
- transcript notification;
- LLM;
- ordered LLM/output processing;
- TTS.

A pipeline unit owns the queues, conversation, cancellation scope, and speculative revision tracker. Multiple `--num_pipelines` values create multiple full chains and model instances, which is the wrong scaling mechanism for large models on unified memory.

### Patterns worth preserving

1. **Turn and revision IDs.** If the user resumes after an apparent endpoint, the new audio is a revision of the same turn. Results from older STT, LLM, or TTS work can be identified as stale.
2. **Generation-stamped cancellation.** A monotonic cancellation generation is safer than scattered timing flags. Every transcript, response, and audio chunk can prove it still belongs to the active generation.
3. **Ordered text, tool, and audio events.** Assistant text and its matching TTS inputs share ordering, preventing terminal events or tool calls from overtaking speech.
4. **Authoritative final transcripts.** Partial ASR is useful for display but should not mutate history arbitrarily; the final transcript is authoritative.
5. **Speculative turn grace.** Silero supplies an acoustic boundary, while Smart Turn decides whether a thought is likely complete. A brief reopen window catches natural pauses before expensive downstream work becomes committed.
6. **Clean session release.** Every handler receives session end; an undrained chain is quarantined rather than leaking a prior conversation into reuse.
7. **Transport symmetry.** `serve`, `talk`, and `local` use the same northbound protocol rather than inventing an untested in-process mode.
8. **Client-owned tools.** The server emits a typed function call; the trusted client executes it and returns the result. Audio transport does not acquire arbitrary tool authority.

### What should not be copied

- NVIDIA/CUDA Docker packaging and loose mutable Python dependencies;
- Hub, NLTK, or model downloads during import/startup;
- one environment containing every STT, LLM, and TTS backend;
- a 16 kHz internal bus for high-fidelity `/speak` output;
- unbounded inter-stage queues;
- per-session duplication of all model weights;
- PortAudio device indexes instead of explicit PipeWire routes;
- unauthenticated exposure outside loopback;
- its Parakeet “progressive streaming,” which repeatedly decodes a growing window rather than using the cached streaming path already present in Voxtype.

The repository has an OpenAI Realtime-compatible subset over WebSocket and WebRTC. That protocol surface is a useful northbound target. It does not make the repository’s model packaging a good fit for gfx1151/NixOS.

## Proposed local component boundary

```text
speech-agent (state, sessions, cancellation, tools)
   ├── capture adapter       PipeWire / WebRTC / phone
   ├── wake + VAD adapter    tiny CPU services
   ├── ASR adapter           current Voxtype/Parakeet events
   ├── agent adapter         Pi RPC first; Codex/Claude/OpenClaw bridges later
   ├── TTS adapter           same logical voices used by /speak
   └── playback adapter      explicit PipeWire route or WebRTC return track
```

Each large model remains independently packaged and can be warm, cold, or replaced. The session service owns no model cache and does not silently download weights. This also permits `/speak` to use the same Qwen/OpenMOSS voice while retaining a different chunker, native sample rate, and completion contract.

The `speech-loop` should expose one transport-neutral event protocol to desktop, phone, and tests:

```text
input_audio / transcript_delta / transcript_final
turn_started / turn_revised / turn_cancelled
agent_text_delta / agent_text_final / tool_event
audio_started / audio_chunk / audio_stopped / response_done
```

Every event carries session, turn, revision, response, and cancellation-generation identifiers. Bounded queues and a one-clause look-ahead prevent minutes of obsolete speech from accumulating.

## Turn-taking progression

### Stage 1: deliberate half-duplex

- Wake or push-to-talk opens capture.
- A chime/indicator confirms capture.
- VAD plus endpointing closes the utterance.
- Parakeet produces a final transcript.
- The agent responds and TTS plays.
- Microphone acceptance is suppressed while local speakers play.

This is the correct baseline. It isolates ASR, agent time-to-first-token, synthesis time-to-first-audio, and playback without an echo loop.

### Stage 2: speculative work and cancellation

- Partial transcripts can prewarm or tentatively start agent work.
- Turn/revision tags ensure resumed speech invalidates old work.
- Incremental agent sentences can reach TTS before the full answer is complete.
- Bounded queues prevent a fast text producer from generating minutes of stale audio.
- A stop command immediately advances cancellation generation and clears unsent/playback buffers.

### Stage 3: barge-in/full duplex

Full duplex is primarily an audio-front-end problem. A speaker-room implementation needs a PipeWire WebRTC echo-cancel source/sink pair, and every TTS sample must traverse the reference sink. Otherwise the system hears itself, triggers its wake word, and transcribes its own response.

WebRTC clients on phones/headsets often provide a better initial full-duplex surface because their audio stack already includes acoustic echo cancellation, automatic gain control, jitter buffering, and Opus transport. Even then, the server must truncate conversation history to what was actually heard when an interruption occurs.

## Latency should be measured by phase

“The turn took 2 seconds” hides the actionable cause. Record:

- wake candidate and verification latency;
- speech-start and endpoint delay;
- partial and final ASR delay;
- agent time to first meaningful text;
- TTS request to first playable audio;
- buffered audio ahead of playback;
- user-end-of-speech to first audible response;
- cancellation request to silence;
- realtime factor and memory for every model.

The reading pipeline optimizes fidelity and job completion. The conversational pipeline optimizes first audio, interruptibility, and bounded buffering.

## Translation

The AMD SeamlessM4T playbook is a useful separate experiment:

```text
captured turn → SeamlessM4T target language → translated speech
```

But the published demo processes complete WAV files and does not preserve a selected assistant identity. A more controllable agent path is often:

```text
Parakeet/source ASR → translated text → selected local TTS voice
```

This keeps the transcript inspectable and the voice consistent, while SeamlessM4T can be evaluated where direct speech translation or its wider language coverage is valuable.

## Control boundary

- Tool calls remain typed, logged, and client-owned.
- Each voice surface maps to an explicit agent session, working directory, and tool profile rather than silently inheriting whichever coding session happens to be active.
- Actions waiting for user confirmation must be represented as explicit harness events so the speech layer can announce the pending state without inventing a paraphrase.
- Cancellation must stop speech immediately without silently approving an action already queued.

## Decision

Do not deploy the Hugging Face repository as the all-in-one stack. Preserve its strongest protocol and state ideas in a small local `speech-agent` that calls already-owned services. Build and benchmark `/speak` first; then implement half-duplex conversation; only then decide whether full-duplex complexity earns its cost.


---

# Wake-word implementation on Strix Halo

## Decision

The first real solution on this machine should be a coordinator-only `speech-wake` user service with this pipeline:

```text
PipeWire default source, 16 kHz mono S16
  → 2.5-second RAM ring
  → pyopen-wakeword `hey_jarvis` candidate, CPU
  → sherpa-onnx exact-phrase verifier, CPU
  → acknowledgement chime
  → existing Voxtype/Parakeet command capture
```

This is an implementable awake-workstation design, not a description of Alexa. The detector is cheap keyword spotting, not continuous ASR. It runs only while Linux and the user session are awake; suspend-time wake would require an external always-on satellite.

## Why CPU is the Strix Halo choice

The coordinator already exposes its XDNA2 NPU and gfx1151 Radeon iGPU, but the correct standby target is one Zen 5 CPU thread:

- [`pyopen-wakeword`](https://github.com/rhasspy/pyopen-wakeword) is a precompiled TensorFlow Lite CPU pipeline. The pinned Nixpkgs version is `1.1.0` and includes `hey_jarvis`.
- The packaged [`sherpa-onnx`](https://k2-fsa.github.io/sherpa/onnx/kws/) KWS path uses CPU ONNX Runtime. The pinned Nixpkgs version is `1.13.3`.
- Upstream openWakeWord processes 80 ms frames and reports that one Raspberry Pi 3 core can run roughly 15–20 models in realtime. On the Ryzen AI Max+ 395, one detector and an occasional verifier should be a very small CPU load. That is an inference to measure, not a claimed watt figure.
- AMD’s current Ryzen AI material demonstrates generic ONNX compilation and speech recognition on the NPU, but it supplies no supported openWakeWord or sherpa KWS recipe for Linux Strix Halo. NPU deployment would require graph compatibility work, compilation/cache packaging, and proof that transfers and wake-up overhead do not dominate this tiny batch-one stream. See AMD’s [model deployment path](https://ryzenai.docs.amd.com/en/latest/modelrun.html) and [RyzenAI-SW](https://github.com/amd/RyzenAI-SW).
- The iGPU should remain available for the existing MIGraphX Parakeet path and TTS. Keeping gfx1151 awake for a three-million-parameter standby model has no evidenced advantage.

Revisit XDNA2 only after a seven-day CPU baseline. Promote an NPU build only if it preserves wake accuracy and p95 latency while reducing measured package-power delta materially—30% is a sensible gate. TOPS alone is not evidence.

## Exact components and starting configuration

### Audio owner

One long-lived `pw-record` process targets the stable iContact node already declared in `hosts/coordinator/audio.nix`:

```text
pw-record \
  --target alsa_input.usb-DCX-241206-FAY_iContact_Camera_Pro_01.00.00-02.analog-stereo \
  --rate 16000 \
  --channels 1 \
  --format s16 \
  --raw -
```

PipeWire `1.6.8` is already pinned locally. The supervisor reads the raw stream, divides it into the detector’s required frames, and retains the latest 2.5 seconds in RAM. It never writes standby audio to disk. [`pw-record`/`pw-cat`](https://pipewire.pages.freedesktop.org/pipewire/page_man_pw-cat_1.html) accepts a `node.name` as its target and supports raw PCM. If the named webcam is absent, the service should enter a visible degraded state or explicitly fall back to automatic default selection according to configuration; it must not silently claim to be listening to the preferred route.

The current iContact Camera Pro source is already selected declaratively in `hosts/coordinator/audio.nix`. Before judging KWS accuracy, confirm that its ALSA `Mic Capture Volume` has not returned to zero; the known recovery is `amixer -c Pro sset Mic 36% cap`. An always-on detector makes silent-input health reporting mandatory: expose current RMS, selected node, and time since the last non-silent frame.

### Stage 1: trained candidate detector

Use Nixpkgs `python313Packages.pyopen-wakeword` `1.1.0`, model `Model.HEY_JARVIS`, TFLite CPU. It accepts 16-bit, mono, 16 kHz audio. Start with:

```text
candidate threshold       0.50
consecutive confirmations 2
refractory period         2.0 s
```

The trained `hey_jarvis` model is preferable to running full ASR continuously. Its classifier has already seen synthetic positives, near-homophones, noise, music, podcasts, and reverberation; upstream’s [model description](https://github.com/dscripka/openWakeWord/blob/main/docs/models/hey_jarvis.md) also notes that same-device playback remains a hard case.

### Stage 2: independent exact-phrase verifier

After a candidate, reset a sherpa stream and replay the 2.5-second ring through `sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20`:

```text
model                   chunk-8
encoder and joiner      INT8
decoder                 FP32
provider                CPU
threads                 1
keyword score           1.0
keyword threshold       0.25
accepted keyword        HEY_JARVIS only
```

The model is approximately three million parameters. Its documented chunk-8 algorithmic latency is 160 ms; chunk-16 is 320 ms and can be compared if accuracy is weak. The shipped English lexicon contains `JARVIS`, so the documented `text2token` flow can compile `HEY JARVIS @HEY_JARVIS` without an out-of-vocabulary workaround. See the [exact pretrained model and quantization combinations](https://k2-fsa.github.io/sherpa/onnx/kws/pretrained_models/index.html).

This verifier is invoked only for candidates, so its average standby cost is negligible. It rejects phonetic spikes that survive the first model without requiring a second full ASR instance.

## Service and state machine

Declare a Nix-built `systemd --user` service, parallel to `voxtype.nix`:

```text
Unit:
  After/Wants = pipewire.service wireplumber.service voxtype.service

Service:
  Restart = on-failure
  RuntimeDirectory = speech-agent
  no network access or listening socket
```

Its operational states are:

```text
MUTED
  └─ explicit enable → STANDBY

STANDBY
  pw-record + 2.5 s ring + openWakeWord
  └─ candidate → VERIFY

VERIFY
  replay ring to sherpa
  ├─ reject → reset detectors → STANDBY
  └─ exact match → ACK

ACK
  freeze ordinary wake acceptance, play local chime
  └─ start Voxtype file capture → COMMAND

COMMAND
  wait for speech; endpoint after trailing silence
  ├─ no speech for 5 s → cancel → STANDBY
  ├─ hard limit 30 s → stop
  └─ 800 ms trailing silence → stop Voxtype → AGENT

AGENT
  wait for authoritative transcript file, dispatch to speech-loop/Pi
  └─ response clauses → TTS → SPEAKING

SPEAKING
  suppress ordinary wake acceptance
  allow explicit stop/cancel path
  └─ playback complete + 500 ms cooldown → STANDBY
```

The supervisor publishes state, selected source, score, and timing events to a private runtime socket or status file so a Niri/Waybar indicator can distinguish standby, verifying, recording, thinking, and speaking.

## The integration that works today

Voxtype `0.7.5` already supports external control:

```text
voxtype record start --file=/run/user/$UID/speech-agent/turn.txt
voxtype record stop
voxtype record cancel
```

This reuses the resident `parakeet-unified-en-0.6b` ONNX/MIGraphX service declared in `home/voxtype.nix`, including its true cached streaming configuration. It does not load another Parakeet model or adopt the batch/progressive decoder from the Hugging Face demo.

The reliable first interaction is deliberately two-stage:

```text
Tom:     “Hey Jarvis”
machine: [chime]
Tom:     “Read the current report.”
```

The supervisor calls `record start --file=...` immediately before the chime completes, owns endpoint timing, calls `record stop`, and waits for a non-empty final transcript. The chime is both feedback and a clean boundary that prevents the first command word from being lost.

## Why one-breath input needs one code change

This form is not lossless with the current CLI:

```text
“Hey Jarvis, read the current report.”
```

Voxtype opens its own microphone after `record start`; it cannot consume the wake supervisor’s pre-roll. The first command word may already be in the 2.5-second ring before Voxtype starts. Running `voxtype transcribe` on a WAV is not a good fix because it bypasses the resident daemon and creates a second ASR lifecycle.

The durable one-breath design is:

1. `speech-wake` becomes the sole PipeWire capture owner.
2. Voxtype gains a daemon IPC/FD operation: `begin external turn`, raw 16 kHz mono S16 frames, then `end` or `cancel`, plus an output target.
3. Sherpa’s wake timestamps identify the wake-word end.
4. The supervisor discards audio through that boundary and feeds buffered post-wake samples plus live frames into the resident Parakeet streaming session.

The existing 2.5-second ring is sufficient. Until that raw-PCM ingress exists, retain the honest chime-then-command UX.

## Stopping and barge-in

Room-speaker full duplex is not part of this first service. While local TTS plays, normal `hey_jarvis` acceptance is inhibited so the assistant cannot summon itself. Provide an independent stop path first: keyboard/button cancellation and, if hands-free stop is required, a narrowly trained `stop` detector operating against a PipeWire echo-cancelled source.

Natural speech-over-speech interruption requires an acoustic echo-cancel reference containing the exact playback samples. That belongs in the later `speech-loop`/WebRTC phase, not in the wake service.

## Acceptance gates

Run the iContact/GS3 far-field and INZONE headset routes separately:

| Gate | Promotion target |
|---|---|
| Deliberate wake acceptance | At least 95 of 100 across distance, angle, normal/quiet voice, fan and music |
| Wake latency | p95 phrase-end to chime at or below 500 ms; verifier never blocks over 750 ms |
| Command boundary | 50 chime-separated commands per route with zero clipped first words and zero premature stops |
| Dark run | Seven days with zero post-verifier false activations |
| Idle resources | Under 5% of one logical CPU, RSS under 250 MiB, median package-power delta under 1 W |
| Recovery | Unplug/replug, default-route change, lock, suspend/resume, Voxtype restart, and TTS cooldown all return to standby |

The resource numbers are gates, not measurements already achieved. Log scores and timing by default, not raw audio. During a short explicit calibration window, test podcasts, films, music, the eventual assistant voice, actual “Hey Jarvis” media, and near-homophones. Exact external speech of the phrase is a genuine match; the second stage cannot magically know whom it was addressed to.

## Custom phrase path

The MVP needs no training. Sherpa can trial arbitrary typed phrases immediately. If a private phrase proves substantially more reliable, train a dedicated openWakeWord model and retain sherpa as the exact-phrase verifier. LiveKit’s newer [`livekit-wakeword`](https://github.com/livekit/livekit-wakeword) provides a reproducible synthetic-data, augmentation, export, and DET/FPPH evaluation pipeline, but its runtime/training surface is newer and not needed to ship `hey_jarvis` first.

The first implementation decision is therefore complete: CPU OpenWakeWord candidate, CPU sherpa verifier, exact PipeWire source, two-stage Voxtype bridge, and measured promotion gates. XDNA2 remains an evidence-driven optimization experiment rather than a prerequisite.


---

# Calling the local agent from a phone

## Recommendation

The existing Tailscale mesh is already the right private access plane. Start with a phone app that calls an OpenAI-compatible local gateway over the tailnet. Do not begin with SIP, a public telephone number, or a new VPN.

The cheapest useful first experiment is **Lemonade Mobile as a client without committing to Lemonade as the server/runtime**.

The source confirms the important intuition: the app already has the phone-side inputs needed for a real probe—microphone capture, OS audio-session routing, on-device Silero VAD, partial/final ASR events, chat history, TTS playback, Bluetooth handling, and a loop that reopens capture. What it does not yet have is a natural full-duplex media clock.

## What Lemonade Mobile actually does

[`lemonade-sdk/lemonade-mobile`](https://github.com/lemonade-sdk/lemonade-mobile) is an MIT Flutter app with iOS and Android distributions. Its source accepts Lemonade or OpenAI-compatible servers. The current “duplex” session is explicitly half-duplex:

1. on-device Silero VAD controls capture;
2. PCM16 is streamed to ASR over WebSocket when available, with HTTP fallback;
3. the final transcript is sent to `/v1/chat/completions`;
4. the app requests `/v1/audio/speech`;
5. it waits for the complete audio file, plays it, and then reopens the microphone.

There is no mid-sentence barge-in, and current TTS playback is not first-chunk streaming. This is still an excellent Stage-0 test of the interaction model, endpoint delay, route quality, and whether a foreground “call my computer” surface is compelling.

The minimum gateway surface is:

```text
POST /v1/audio/transcriptions  → Parakeet or selected ASR
POST /v1/chat/completions      → current agent/LLM route
POST /v1/audio/speech          → selected TTS adapter
```

For this machine, that can be a thin `speech-gateway`, not Lemonade Server:

```text
Lemonade Mobile over Tailscale
  /v1/audio/transcriptions → adapter to Parakeet/Voxtype or speech-loop ASR
  /v1/chat/completions     → dedicated Pi RPC/session bridge
  /v1/audio/speech         → qwen3-tts.cpp or selected OpenAI-shaped TTS
```

The gateway owns authentication, request limits, model-name translation, and one phone-specific session. It exposes no model download, unload, shutdown, or general host-management methods. This preserves Lemonade Mobile as a replaceable client and leaves `hardware.amd-npu.enableLemonade = false` intact.

There are two integration levels:

1. **Stage 0, no new realtime protocol:** accept HTTP transcription fallback, use a normal chat completion, return one complete MP3/WAV. This matches the app today and is enough to evaluate phone UX and total turn latency.
2. **Stage 1, lower latency:** satisfy the app’s realtime ASR discovery/WebSocket contract for partials, but TTS still waits for a complete artifact. Moving beyond that needs a client change or a different WebRTC surface.

The app’s `DuplexVoiceSession` source explicitly labels full duplex out of scope, and `TtsService` writes the complete response to cache before playback. Therefore Lemonade Mobile has the right control inputs, but it is not evidence that installing Lemonade’s whole server would add barge-in or streaming playback.

Optional realtime transcription uses Lemonade-specific health discovery for a WebSocket port. The first test can accept HTTP transcription fallback or place that port behind the same gateway.

Current mobile manifests do not establish a fully background-capable VoIP endpoint. Treat it as “open app, tap call, keep foreground” until physical tests prove otherwise. Hosted Nexus sign-in, phone numbers, IVR, voicemail, and managed services are unrelated to the private local experiment and should be skipped.

An Android alternative worth a later comparison is [`WakeHermesClaw`](https://github.com/yuga-hashimoto/openclaw-assistant): offline Vosk wake phrases, partial STT, continuous conversation, and OpenClaw/Hermes-compatible agent endpoints. It reaches further toward hands-free wake on the handset, while Lemonade Mobile is the cleaner immediate OpenAI-compatible probe. Neither removes the need for the Strix `speech-loop` if desktop and phone must share sessions and exact interruption semantics.

## Private exposure

The dotfiles already use Tailscale declaratively and already contain the appropriate firewall pattern: bind deliberately, leave the general firewall closed, and allow only `tailscale0`.

Preferred options:

1. Keep the backend on loopback and expose it with **Tailscale Serve HTTPS**. Serve supplies a secure origin and tailnet identity boundary when configured carefully. See [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve).
2. Alternatively bind the narrow compatibility gateway to a host address but open its port only on `tailscale0`, following the existing llama-swap posture.

Do not use Funnel, a raw WAN port, or an unauthenticated `0.0.0.0` inference/control server. Lemonade’s broader server includes management surfaces; if it is ever remotely exposed, use its full inference API key rather than assuming an admin key protects every endpoint. Keep model management off the phone-facing gateway.

Tailscale uses WireGuard encryption and handles roaming/NAT traversal. It first relays and then attempts a direct path; difficult mobile NAT may remain on DERP and add latency. Measure Wi-Fi and cellular with `tailscale ping` rather than adding WireGuard again. See [Tailscale connection types](https://tailscale.com/docs/reference/connection-types) and [iOS VPN On Demand](https://tailscale.com/docs/features/client/ios-vpn-on-demand).

## Options compared

| Surface | Strength | Limitation | When to choose |
|---|---|---|---|
| Lemonade Mobile + Tailscale | Existing native app, VAD/transcript/history, no server commitment | Foreground, half-duplex, whole-file TTS | First experiment |
| Tailnet PWA | Sovereign, very small server/client, easy tap-to-talk | Browser background mic/session reliability is weak | Custom foreground control/read UI |
| Native WebRTC | Opus, jitter handling, AEC, interruption, mobile network recovery | Requires session/media infrastructure and client work | If natural full duplex matters |
| Private SIP over tailnet | Literal extension and native softphone metaphor | PBX/RTP/codec/credential operations | If dialing semantics matter |
| PSTN gateway | Any phone can call a normal number | Cloud/carrier media, public edge, fees, telephony quality | Last-mile reachability, not core |

## WebRTC paths

If half-duplex feels limiting, two current frameworks are relevant:

- [`pipecat-ai/pipecat`](https://github.com/pipecat-ai/pipecat) is pipeline-oriented, supports many local ASR/TTS providers, offers SmallWebRTC for direct peer-to-bot experiments, and can later use LiveKit transports. It may be the fastest research prototype.
- [`livekit/livekit`](https://github.com/livekit/livekit) is a stronger durable media/session plane with native mobile SDKs, self-hosting, JWT room permissions, TURN/network handling, and an optional SIP bridge. Its agent layer explicitly handles interruption, false-interruption recovery, and truncating the response to what the caller actually heard. See [LiveKit turn handling](https://docs.livekit.io/agents/logic/turns/).

LiveKit need only transport media and session events; ASR, LLM, and TTS can remain entirely on the Strix Halo. A token endpoint should issue short-lived, audio-only room grants over the authenticated tailnet.

## SIP and PSTN later

A private SIP service plus a softphone such as Linphone can give “dial my agent” semantics without per-minute charges, but adds registration, RTP ranges, DTMF, echo, codec, credentials, and PBX lifecycle. It is justified only if the telephone metaphor itself is valuable.

PSTN adds reachability without an app or VPN, but audio traverses a carrier/cloud edge, incurs recurring cost, uses telephony codecs, and needs a public SIP/media boundary or managed service. Caller ID is not authentication. A PIN/DTMF challenge and explicit confirmation are required for consequential actions.

There is also a major difference between:

- **Tom opens the app and calls the agent** — straightforward; and
- **the agent can ring a killed/backgrounded phone** — a separate native mobile project involving iOS PushKit/CallKit or Android push/foreground-service restrictions.

Do not let the second requirement silently enter the first prototype.

## Test matrix

For the initial foreground phone call, record:

- Tailscale direct versus DERP path;
- Wi-Fi and cellular;
- live partial and final transcription delay;
- endpointing delay;
- LLM time to first text;
- TTS time to first audible audio and total turn gap;
- Bluetooth/headset/earpiece/speaker routes;
- Wi-Fi-to-cellular handoff;
- screen lock and app background behavior;
- interruption and cancellation behavior;
- whether API credentials remain in platform secure storage.

## Open decisions

- Does “call” mean user-initiated foreground use, or must the agent ring a killed app?
- Must an active session survive screen lock?
- Is half-duplex acceptable initially?
- Must access remain tailnet-only, or is a public number eventually valuable?
- Is any non-tailnet media relay acceptable?
- Which tools are allowed over voice, and what explicit confirmation protects consequential ones?

The answers change the architecture. They need not be answered to run the safe Stage-0 Lemonade Mobile/Tailscale probe.


---

# Bounded evaluation plan

This is a proposed sequence, not authorization to install or deploy it.

## Principle

Answer the cheapest architectural question first. Do not test wake words while the chosen voice is unknown, do not build WebRTC before half-duplex is measured, and do not adopt a broad runtime before its speech backend beats a narrow one.

## Stage 0 — freeze the test material

Prepare one small local corpus before comparing engines:

- a 20-second conversational response;
- a two-minute technical explanation with paths, acronyms, and a short list;
- a 10-minute Markdown document with headings, links, table content, footnotes, and code that needs oral preparation;
- numbers, dates, currencies, punctuation, abbreviations, French names, and mixed French/English;
- an emotional-but-restrained passage;
- an interruption phrase and a wake-word hard-negative set;
- original dry voice-design seed candidates and exact transcripts.

Record every input hash. A model comparison is meaningless if the text preparation or reference voice changes between runs.

## Stage 1 — fast fixed-voice control

Use Kokoro or Supertonic to validate only the `/speak` job mechanics:

- source → spoken normalization;
- chunking and joining;
- native sample rate;
- explicit PipeWire route;
- quiet-hours behavior;
- archive and synthesis/playback receipts;
- cancellation and deterministic completion.

This stage is not a voice-quality selection. It proves the engine-neutral contract cheaply.

Run the default `/speak` path without a utility model and record accepted-to-playing latency. Compare it against `--polish` and `--render` so the durable-paper analogy does not accidentally become the everyday audio latency. Require first-clause streaming, no more than one clause buffered, and explicit `accepted`/`playing`/`played` status.

## Stage 2 — assistant voice bakeoff

Run identical candidates through:

1. both Qwen C++ repositories, with 0.6B/1.7B and relevant quantizations;
2. official Qwen/Python as a quality reference if a bounded ROCm environment is practical;
3. Chatterbox;
4. standalone OpenMOSS/MOSS VoiceGenerator;
5. OmniVoice if the Strix path can be reproduced;
6. VibeVoice only for its long-form role;
7. the small fixed-voice control.

Measure:

| Dimension | Measurement |
|---|---|
| First audio | request accepted → first playable native-rate samples |
| Throughput | realtime factor and long-form wall time |
| Residency | cold/warm load time, peak and steady unified memory |
| Intelligibility | human error log and ASR WER on clean expected text |
| Identity | blind pairwise consistency across texts and durations |
| Prosody | pacing, pause placement, emphasis, sentence-boundary artifacts |
| Drift | timbre, accent, volume, and cadence after 2/10+ minutes |
| Reproducibility | variance across deterministic/seeded repeats |
| Control | response to speed/style/design instructions |
| Operations | build/pin burden, offline startup, crash recovery, API stability |

Keep generated clips blinded by random ID for listening. “Sounds most like Jarvis” should be replaced with explicit ratings: composed, precise, warm, dry, authoritative, non-fatiguing, and recognizably original.

## Stage 3 — `/speak` pilot

Promote one primary voice and one fast fallback into the stable logical registry. Pilot read-aloud jobs from Markdown and stdin for a week. The gate is:

- no silent content loss;
- correct completion reporting;
- route and quiet-hours behavior are unsurprising;
- replay is possible from the archive;
- voice/model revision is always recoverable from the receipt;
- long-form quality is comfortable enough to finish actual documents.

Only after this gate should agent auto-speech events be enabled.

## Stage 4 — wake-word dark test

Run the exact proposed CPU cascade—pyopen-wakeword `hey_jarvis` candidate plus sherpa exact-phrase verifier—without launching ASR or the agent. Log only events and score/timing summaries; retain raw audio only during an explicitly enabled, short-lived calibration window. Compare an arbitrary private phrase through sherpa, but do not postpone the known-model baseline for phrase training.

Test both webcam/GS3 and INZONE routes separately for 24–72 hours, including:

- silence and normal work;
- music, films, calls, keyboard, vacuum/fan;
- every candidate TTS voice saying technical material;
- deliberate near-misses and varied wake distances;
- actual Marvel/Jarvis media as hard negatives;
- lock, suspend/resume, route change, and mute transitions.

Promote only if post-verifier activation is below the chosen nuisance budget and wake-to-chime latency remains comfortable. The aspirational target is below one unintended activation per week in the real room.

## Stage 5 — desktop half-duplex conversation

Build the smallest state machine:

```text
wake → chime → capture → Parakeet final → agent → TTS → idle
```

The first agent adapter is a dedicated Pi RPC session. Measure `prompt` acceptance, agent first meaningful text, first safe clause, TTS first PCM, playback start, and final `message_end`. Test `abort`, `steer`, and `follow_up` while a run is active, but keep acoustic speaker barge-in disabled.

No speaker barge-in. Record phase latency, stale-work cancellation, transcript authority, explicit confirmation, and whether a short follow-up window is actually useful. Do not enable arbitrary tools merely because the agent is reachable by voice.

## Stage 6 — phone Stage-0

Point Lemonade Mobile at a narrow disposable compatibility gateway over Tailscale. Implement only `/v1/audio/transcriptions`, `/v1/chat/completions`, and `/v1/audio/speech`; do not install Lemonade Server for this probe. Keep the app foreground and accept half-duplex. Measure direct/DERP behavior, Wi-Fi/cellular, Bluetooth, screen lock, and turn gaps.

This test answers whether phone access is valuable without deciding on Lemonade Server, WebRTC, SIP, or PSTN.

## Stage 7 — conditional branches

Only branch when measurements justify it:

- **Long-form weakness:** evaluate/finish the Kyuz0 VibeVoice Nix translation.
- **Identity weakness:** compare Chatterbox/OpenMOSS/OmniVoice with the same original seed.
- **Half-duplex adequate:** keep the simple conversation path.
- **Barge-in essential:** prototype Pipecat SmallWebRTC, then decide whether LiveKit should become the durable media plane.
- **Literal phone metaphor essential:** add private SIP after WebRTC/local semantics are stable.
- **App/VPN-independent reachability essential:** price and threat-model PSTN last.
- **Suspend-time wake essential:** prototype an external microWakeWord satellite rather than forcing an awake CPU design into suspend.

## Reproducibility receipt

Every benchmark result should include:

- source repository and exact commit;
- model repository, exact revision, and artifact hash;
- engine build options and quantization;
- Nix derivation/environment revision;
- kernel, Mesa/Vulkan/ROCm/TheRock versions;
- text and reference-audio hashes;
- logical voice and registry revision;
- random seed/sampling settings;
- cold/warm state;
- output format, native rate, route, and measurement method;
- peak memory and phase timings;
- generated artifact link.

## Decisions to make before implementation

1. Which local profile should be primary: the Jarvis-style designed voice or the literal K-2SO/Alan Tudyk clone?
2. Is `/speak` allowed to paraphrase for listening, or must verbatim be the default?
3. During quiet hours, are explicit headphone requests allowed while speakers remain render-only?
4. After the proven two-stage wake release, how soon should the Voxtype raw-PCM ingress needed for lossless one-breath input be prioritized?
5. Should wake standby pause at lock?
6. Is half-duplex acceptable for the first desktop and phone versions?
7. Does phone access remain tailnet-only?
8. Which tool classes are permitted through voice, and which require a visual/second-factor confirmation?

The first three technical experiments can proceed independently after those policy choices: `/speak` mechanics with a fixed control voice, voice-design bakeoff, and a non-activating wake-word dark test.


---

# Recommended final stack and component ownership

## The recommendation in one view

The local speech system should be a small set of independently owned services, not one imported assistant platform:

```text
                              ┌─────────────────────────────┐
prepared Markdown / stdin ───>│ /speak fast or render mode │──────┐
                              └─────────────────────────────┘      │
                                                                   ▼
desktop mic ──> speech-wake ──> speech-loop <──> agent adapter ──> TTS adapter ──> PipeWire
                  CPU KWS         media clock       Pi RPC first       Qwen C++
                    │                 ▲                                  │
                    │                 │                                  └─ logical voice registry
                    ▼                 │
             Voxtype/Parakeet ────────┘

phone app ── Tailscale ──> narrow speech-gateway ──> same speech-loop / agent / TTS
```

The first promoted path should be intentionally half-duplex. Every component boundary already permits a later WebRTC transport and real barge-in without replacing the agent brain, voice registry, or model services.

## Component ownership

| Component | Owns | Does not own | First choice |
|---|---|---|---|
| `/speak` command/skill | user intent, oral mode, durable job/receipt | model process, mic, conversation | deterministic fast path; optional `--polish`; `--render` archive |
| `speech-wake` | PipeWire standby capture, 2.5 s ring, KWS, chime, state | ASR model, agent, TTS model | pyopen-wakeword + sherpa verifier on CPU |
| Voxtype | resident streaming English ASR model | wake policy, agent session | existing Parakeet ONNX/MIGraphX daemon |
| `speech-loop` | active turn state, endpointing, cancellation, safe clauses, heard-text ledger, playback | durable agent reasoning, model downloads | small Nix-built user service |
| agent adapter | prompts, session, tools, streamed response events | microphone, audio queue | Pi RPC first |
| TTS adapter | engine-neutral speech API and voice resolution | document semantics, playback policy | Qwen3-TTS C++ winner, Kokoro fallback |
| voice registry | logical IDs, references, prompts/embeddings, revisions | engine lifecycle | `assistant-main`, `assistant-fast`, `narrator-long` |
| phone gateway | tailnet auth, three narrow APIs, phone session mapping | general model or host management | loopback + Tailscale Serve or `tailscale0` firewall |
| WebRTC transport, later | media transport, jitter/AEC client path, session signaling | ASR/LLM/TTS ownership | Pipecat prototype; LiveKit if durable plane is needed |

## The two product paths

### `/speak`: read prepared material

Default behavior:

```text
agent-authored final text
  → deterministic oral normalizer
  → first safe clause
  → warm TTS stream
  → explicit PipeWire route
```

No second model is required. Use `--polish` only when the text genuinely needs oral restructuring, and `--render` when a replayable complete artifact and validation receipt matter. Quiet hours may render but must not surprise-start speakers later.

### `speech-agent`: converse

First release:

```text
Hey Jarvis → verify → chime → command → Parakeet final
  → Pi prompt → streamed answer clauses → Qwen TTS → playback → standby
```

The media controller tags every turn/revision and cancels stale text and audio. Pi remains the agent brain because its RPC already exposes sessions, streamed updates, tools, steering, follow-up, and abort. Codex, Claude Code, Hermes, or OpenClaw can later receive separate adapters without changing the audio side.

## Engine assignments

### Primary conversational and reading voice

Benchmark both current Qwen C++ implementations on Vulkan and choose by measured first-audio latency, identity, stability, and packaging:

- [`ServeurpersoCom/qwentts.cpp`](https://github.com/ServeurpersoCom/qwentts.cpp): broader C ABI, Q8/Q4, pre-encoded speaker/codec artifacts, and voice registry surface.
- [`khimaros/qwen3-tts.cpp`](https://github.com/khimaros/qwen3-tts.cpp): simple GGML/Vulkan build, OpenAI-compatible server, multipart cloning, voice design, and streaming PCM.

Use the winner behind the logical API; do not make callers know its model filename. A small Kokoro service is the fixed-voice control and emergency fast fallback.

### Identity challengers

- Chatterbox: short-reference clone quality.
- OpenMOSS/MOSS-VoiceGen: cloning plus text-described voice design; Lemonade can be one bounded backend experiment but is not required.
- VibeVoice Large/Kyuz0 path: long-form and multi-speaker specialist, loaded on demand.
- OmniVoice: evaluate if its Strix C++ path becomes reproducible.
- ACE-Step: separate music service, never a TTS fallback.

### Voice profiles

1. `assistant-main`: whichever Jarvis-style or K-2SO profile wins conversational quality and latency.
2. `assistant-fast`: small built-in voice for chimes, errors, and cold-start acknowledgements.
3. `narrator-long`: the most stable ten-minute voice, potentially VibeVoice or a higher-quality Qwen mode.

The two-plus-minute K-2SO corpus becomes a segmented, exactly transcribed reference bank. Derive 3, 6, 10, 20, 30, 60, and 120 second variants, retain a held-out set, and precompute the winning engine’s enrollment artifact. The complete corpus is not uploaded or reparsed on each request.

## Desktop deployment sequence

### Phase A — prove the voice and fast reading

1. Package a fixed-voice control and `/speak` fast/render modes.
2. Benchmark both Qwen C++ servers with designed Jarvis candidates and the K-2SO reference bank.
3. Promote one primary voice plus one fallback into the registry.
4. Pilot real Markdown reading for a week. Measure command-to-first-audio, content loss, cancellation, route behavior, and long-form fatigue.

### Phase B — ship actual wake plus half-duplex conversation

1. Package `speech-wake` with exact PipeWire source, pyopen-wakeword, sherpa verifier, runtime state, and health reporting.
2. Dark-run for seven days without dispatching the agent.
3. Enable the chime-then-command Voxtype bridge.
4. Add `speech-loop` and a dedicated Pi RPC session with a deliberately scoped working directory/tool set.
5. Keep ordinary wake inhibited during local TTS; keyboard/button stop works immediately.

### Phase C — remove latency and turn roughness

1. Keep Qwen warm and cache the selected voice representation.
2. Speak the first safe answer clause while the agent continues.
3. Add turn/revision generation IDs and bounded one-clause buffering.
4. Add Voxtype raw-PCM daemon ingress so wake pre-roll supports one-breath commands without duplicating Parakeet.
5. Add semantic endpointing only after acoustic timing is measured.

### Phase D — phone and full duplex

1. Point Lemonade Mobile at the three-route gateway over Tailscale; accept its foreground half-duplex behavior.
2. If it is pleasant enough, keep the replaceable client and improve only the gateway/engines.
3. If barge-in is essential, prototype Pipecat SmallWebRTC with all inference local.
4. Promote LiveKit only if durable native mobile sessions, TURN, or later SIP justify the media plane.
5. Add SIP/PSTN only if literal dialing or app/VPN-independent reachability becomes a real requirement.

## What is deliberately not in the stack

- no all-in-one Hugging Face speech-to-speech Python environment;
- no complete Lemonade server merely for its mobile app or speech endpoint;
- no OpenClaw/Hermes/Jarvis platform migration merely to copy their voice loop;
- no second resident Parakeet instance;
- no XDNA wake detector without a measured power/latency advantage;
- no full-WAV wait on the default `/speak` path;
- no always-running VibeVoice Large simply because unified memory can hold it;
- no unauthenticated inference endpoint outside loopback/tailnet;
- no ordinary wake acceptance while the assistant speaks until AEC is proven.

## Key measurements before implementation choices harden

| Decision | Evidence required |
|---|---|
| Qwen implementation | identical corpus, clone artifact, quantization, cold/warm first audio, realtime factor, RSS, ten-minute drift |
| Jarvis vs K-2SO primary | blind identity, comfort, technical pronunciation, latency, stability |
| warm daemon policy | idle memory/power versus avoided cold-start delay |
| CPU wake promotion | seven-day false activations, >=95% deliberate accepts, p95 phrase-end-to-chime <=500 ms, <1 W median package delta |
| one-breath work | demonstrated command loss with current bridge; raw-PCM Voxtype API design and end-to-end test |
| Lemonade Mobile retention | Wi-Fi/cellular turn gap, direct/DERP, Bluetooth, screen lock, foreground behavior |
| WebRTC adoption | measured need for barge-in/AEC/network recovery, not architectural enthusiasm |

## Final recommendation

Proceed conceptually with **Qwen-first `/speak` + CPU `hey_jarvis` wake + current Parakeet + `speech-loop` + Pi RPC**, all as separately pinned Nix services. Use **Lemonade Mobile only as the first phone client over Tailscale**. Borrow realtime semantics from Hugging Face, OpenClaw, and Hermes; do not adopt their full runtimes. The next implementation phase should begin with voice bakeoff and fast `/speak`, then dark-run the wake service, then join them through the half-duplex controller.
