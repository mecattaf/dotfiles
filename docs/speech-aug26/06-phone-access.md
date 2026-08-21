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
