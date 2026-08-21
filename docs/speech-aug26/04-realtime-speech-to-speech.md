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
