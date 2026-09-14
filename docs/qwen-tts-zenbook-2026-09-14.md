# Qwen speech on Strix Halo, played by the Zenbook

2026-09-14. Initial re-entry brief, retained as the starting rationale.
The later instructions broadened this into a measured comparison of Qwen
packages, VibeVoice TTS, C++ inference and streaming diarized ASR. Runtime
selection remains open. See [the evolving build plan](qwen-tts-build-plan.md)
and the results in `~/tts-audition-20260914/` for current implementation state;
statements below about unavailable files describe the start of this work.
Branch: `work/qwen-tts-zenbook`, based on dotfiles `3a300271`.

## Decisions carried forward

Tom's current instruction selects **Qwen TTS** and places playback on the
**ASUS Zenbook Duo (`client`)**. The target is Alan Tudyk's K-2SO performance;
a similar voice is acceptable if the clone proves unsatisfactory.

The authoritative earlier annotations are
[`annotations-local.md`](../../notes/mykonos/annotations-local.md), especially
section 3. Their standing requirements are:

- Verbatim transcription; do not rewrite dictated speech.
- Use the client's selected microphone and output, including attached devices.
- Call transcription must disable wake detection.
- K-2SO first; Jarvis was a fallback, not an equally preferred voice.
- Varied, witty listening acknowledgements; time-of-day variants are desirable.
  Matching the user's intonation remains an experiment.
- The language-model layer delegates work to the appropriate agent/tools.
- `/speak` and reading arbitrary selected surfaces are desired utilities.
- Display-off is a normal state; hands-free wake is not the first priority.

The August report's broad engine comparison is historical. Qwen was the
initial choice; Tom subsequently requested a fresh comparison with VibeVoice
before selecting the final runtime. The Gemma/FastFlowLM NPU routing proposal is superseded by
the 2026-08-29 retirement in [`AGENTS.md`](../AGENTS.md). Use the existing
Halogen utility route where language understanding is needed.

## Current implementation ground truth

[`home/voxtype.nix`](../home/voxtype.nix) now implements client microphone → SSH
→ coordinator Parakeet → transcript returned to client. It uses **batch
`parakeet-tdt-0.6b-v3`**, not the August report's streaming unified model.
Its September 13 evidence explains that change and records 0.21-second warm
inference for a 5.8-second fixture. Those are ASR measurements, not TTS results.

[`hosts/client/audio.nix`](../hosts/client/audio.nix) prioritizes the dock's
iContact microphone and Sound Blaster GS3 output. The audio picker can change
the selected devices. Playback should follow the client's selection rather
than hard-code the dock speaker or use the coordinator's default sink.

There is no Qwen TTS artifact in `lib/local-models.nix` at this baseline and no
Qwen speech service. The old report's claim of two minutes of clean local K-2SO
audio has not been verified. Do not treat it as an available reference bank.

## Model and engine recommendation

**Start with `Qwen/Qwen3-TTS-12Hz-1.7B-Base`, Q8_0, using
`ServeurpersoCom/qwentts.cpp` with Vulkan on the coordinator.** This is an
implementation recommendation, not a measured speed winner. Keep a higher
precision control for voice-quality comparison.

The [official Qwen implementation](https://github.com/QwenLM/Qwen3-TTS)
distinguishes Base reference cloning, CustomVoice presets, and 1.7B VoiceDesign
for text-described voices. Base accepts audio plus its exact transcript and
can reuse a precomputed conditioning prompt. Its documented design-then-clone
workflow lets an original designed voice become a stable Base reference.
Use **1.7B VoiceDesign for enrollment only** if the K-2SO reference does not
work, then serve that voice through Base. Compare **0.6B Base** with the same
reference if 1.7B cannot sustain playback. CustomVoice is not the model to pick
merely because we want a custom clone.

128 GB makes model capacity unlikely to be the deciding constraint. This is
an inference from model scale, not a measured runtime memory budget: GPU
bandwidth, kernel overhead, cold start and competing coordinator jobs still
need measurement. Keep Halogen on the worker and speech on the coordinator.

The [proposed C++ runtime](https://github.com/ServeurpersoCom/qwentts.cpp)
documents Vulkan, Q8/Q4 weights, cloning, voice design, reusable reference
artifacts and a speech HTTP server. Its PCM response streams signed 16-bit,
24 kHz mono audio; WAV responses are buffered. Those capabilities fit the
client route and a persistent logical voice ID. Use its matching codec and
conversion format; GGUF artifacts from different implementations are not
assumed interchangeable.

[`khimaros/qwen3-tts.cpp`](https://github.com/khimaros/qwen3-tts.cpp) is the
second candidate if the first fails quality or latency checks. It documents
Vulkan support, Base/CustomVoice/VoiceDesign, Q8/F16 artifacts, reference
enrollment and chunked audio output.

The hardware-specific
[`haraldh/qwen3-tts-rs` Strix branch](https://github.com/haraldh/qwen3-tts-rs/tree/strix-halo)
reports 1.70 seconds to generate 5.85 seconds of audio on an 8060S with 0.6B
CustomVoice, versus 25.28 seconds cold. This is author-reported whole-utterance
timing, not our benchmark, first-audio latency, or evidence for 1.7B cloning.
It also documents decoder-tail loss and streaming differences plus several
patched dependency forks. Keep it as a performance reference rather than the
initial deployment candidate.

Upstream revisions observed with `git ls-remote` on September 14:

| Repository | Revision |
| --- | --- |
| ServeurpersoCom/qwentts.cpp | `71ad93d591a2811f35db77e27c02acba091c9e9b` |
| khimaros/qwen3-tts.cpp | `0c8b2ba0e7c57a2741852f4305a92996258a71a0` |
| haraldh/qwen3-tts-rs, strix-halo | `6a1d77c9a443f48736144f0b776d6c7a37919096` |

## Voice direction

Tom's [YouTube reference](https://www.youtube.com/watch?v=II1x9ptMZag) resolves
through YouTube metadata to “K2SO Best scenes: Star Wars Rogue One.” Metadata
was checked; the audio has not been auditioned or extracted in this session.
Clone quality and clean segment availability remain untested.

First audition: exact-transcript references of approximately 3, 6 and 10
seconds, each with a single speaker and minimal music/effects. Compare the
same new sentences and a paragraph; keep evaluation dialogue out of the
conditioning set. Preserve the original source and timestamps. Keep this
voice local as specified in the earlier project brief.

Fallback VoiceDesign direction:

> Adult male, low-mid register, precise consonants, clipped measured phrasing,
> little breathiness, restrained pitch variation, dry deadpan delivery and
> understated curiosity. Clear and comfortable for sustained reading.

That is a proposed original voice direction, not a claim that a preset sounds
like Tudyk. Avoid heavy robotic processing until listening demonstrates a
need. Humor belongs in assistant-authored acknowledgements and replies;
verbatim dictation and source text must not acquire jokes. Cache a small set
of **Qwen-rendered** acknowledgements on the client for immediate playback.

## Implementation boundary and first acceptance checks

Proposed route:

```text
prepared text / agent response
  → coordinator: Qwen TTS service and reusable voice profile
  → PCM stream over SSH
  → Zenbook: bounded playback queue → selected PipeWire output
```

The Zenbook owns playback, volume, stop and device selection. The coordinator
owns synthesis. Cancellation must stop upstream generation and discard queued
audio; a disconnected client must not leave a growing job queue. Use a
loopback-bound service through SSH initially. Audio format must be explicit
at both ends. A `/speak` invocation originating in a coordinator shell needs
an explicit route to the attached client session.

Package the engine in Nix and add a dedicated speech module. Put pinned,
hashed weights in the NAS Library catalog and loan them with the existing
`local-models-borrow` workflow. No runtime Hugging Face downloads. Define
on-demand lifecycle, serial admission and warmup; voice design does not need
to remain loaded beside Base.

Before choosing the deployed configuration, measure first audible output
**on the Zenbook**, cold/warm startup, peak memory and generation seconds per
audio second. Test a short acknowledgement, paragraph and ten-minute reading;
listen for reference leakage, repeated words, missing endings, identity drift
and gaps at chunk boundaries. Repeat under ordinary coordinator ASR/browser
load. Verify stop, disconnect, output-device changes and display-off playback.
Require sustained generation faster than playback with useful headroom; no
latency target is claimed achieved yet.

This pass created the isolated worktree and reviewed sources. It did not
download weights, synthesize audio, enable a service or switch either host.
