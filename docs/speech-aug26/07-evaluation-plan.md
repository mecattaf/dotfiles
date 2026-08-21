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
