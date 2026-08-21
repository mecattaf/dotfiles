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
- [Appendix A — Gemma 4 and the local speech stack](09-gemma-4-any-to-any-appendix.md) — 2026-08-14 supplement to the printed report; kept separate from the 2026-08-13 single-file edition

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
- No model was downloaded. The 2026-08-14 appendix loaded the already-installed FastFlowLM Gemma 4 E4B once through the required request-scoped `flm run` boundary, recorded one cold/warm timing probe, and released it on exit; no model service was enabled.
- No always-on microphone service was started.
- No phone, SIP, PSTN, WebRTC, or public endpoint was exposed.
- The K-2SO voice is scoped as permanently local-only, as specified.

Main report research snapshot: 2026-08-13. Gemma 4 appendix snapshot: 2026-08-14.
