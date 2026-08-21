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
