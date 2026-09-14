# Voxtype and client capture: measured integration

Reviewed 2026-09-14. All transcription runs on coordinator. Alexa detection, the nudge, USB microphone capture, transport and playback are client responsibilities. No brightness changes or new model installation on client.

## What Voxtype already handles

The installed Voxtype is push-to-talk software with `record start --file=PATH`, `record stop`, `record cancel` and a standalone `transcribe FILE` command. The existing fleet already routes client `dictate-hold` PCM over SSH into resident coordinator Voxtype through a virtual PipeWire sink/source pair. This is not a microphone physically attached to the coordinator. Mod+Space currently selects the client's default source; the separate Mykonos wake session explicitly pins the iContact USB microphone and refuses fallback. No microphone was opened for this investigation.

Upstream source reviewed at `320a737e5d3c8662e0ec7de95f75407baa784d82`, newer than fleet pin `f97276661d9b723aa3236f03879650a2a06c3ec3`. It has **integration hooks for an external wake detector**, not a bundled Alexa detector: optional external-trigger silence timeout, speech level threshold and stop callback. Its comments explicitly mention OmaPilot. The timeout applies to externally triggered sessions, not ordinary held-key dictation. We do not need to upgrade Voxtype or enable this optional feature: client WebRTC VAD already determines the endpoint.

Sources: [upstream audio configuration](https://github.com/peteonrails/voxtype/blob/320a737e5d3c8662e0ec7de95f75407baa784d82/src/config/audio.rs), [user manual](https://github.com/peteonrails/voxtype/blob/dev/docs/USER_MANUAL.md).

## Fix made

The prototype collected a complete command in RAM and only then invoked the relay. Because the relay feeds a virtual microphone at real-time speed, this added a second utterance-duration wait. `StreamingRelay` now opens SSH when the listening cue finishes, feeds each captured PCM frame immediately, and closes stdin at the VAD endpoint. Voxtype still performs batch inference at the endpoint; **streaming transport does not mean a streaming ASR model**.

Pending transport is capped at two seconds; stalled transport cancels rather than accumulating an entire replay. Call/media inhibition cancels capture and relay and discards pending bytes. The existing single-flight coordinator lock prevents overlapping dictations. Coordinator capture readiness and failed virtual-sink playback now fail closed instead of continuing with incomplete audio. Transcript delivery remains a structured event; this component never types into arbitrary windows or dispatches commands.

The client PlaybackMonitor is integrated and packaged alongside wake.py; the root integration owns that helper and its specific playback policies.

## Saved-file measurement

`python3 tools/speech-intake/benchmark-relay.py` replays the same mono PCM16 16kHz fixtures used for the Gemma comparisons into the coordinator virtual sink. No physical speaker or microphone is involved. Each endpoint is timestamped immediately after `pw-cat` drains, **before** the deliberate 200ms loopback tail wait. Delivered-transcript timestamps therefore include this tail, daemon inference and relay completion. They exclude the client VAD timeout, wake/nudge, SSH return path and agent/TTS stages. This is a resident-model endpoint measurement, not the slower standalone CLI model-reload measurement.

| Exact fixture | Audio seconds | Endpoint to transcript seconds | Result |
|---|---:|---:|---|
| synthetic-short | 8.24 | 0.499 | Correct words |
| human-montage | 8.75 | 0.552 | Correct words; K2SO formatting differs |
| synthetic-technical | 18.24 | 0.781 | Correct words |
| silence | 3.00 | 0.494 | Empty |
| route-request | 6.40 | 0.547 | “Dot Files” and “wakeword” formatting |

Route output: “Ask the coding agent in the Dot Files project to explain the wakeword recording safeguard. Do not change any files.” This is different from the standalone file test's dotfiles spelling: virtual audio ingestion can change the waveform slightly. Do not overwrite or conflate these two results.

Raw measurements: `~/tts-intake-gemma-20260914/runs/parakeet-relay-current.json`. Single runs here are integration checks, not p95 estimates. Actual Tom speech through the USB microphone, network jitter and full wake-to-agent response still require an explicitly coordinated live test.

## Keep Voxtype or serve Parakeet directly?

The existing warm relay is fast enough to keep for this integration, with no new server or model loan. Its liabilities are the virtual audio dependency, 200ms tail, shared recording lock and small waveform changes. A direct resident file API would avoid these, but replacing a measured working MIGraphX backend needs its own validation.

Voxtype's standalone file command avoids the loopback but initializes its model per process; that is not an equivalent resident API. The root's fresh-process comparison also observed SIGABRT on 4 of 15 invocations at teardown, after correct text had been printed, with “corrupted double-linked list” in the logs (`runs/parakeet-file`). Treat this CLI path as an unsafe per-utterance fallback. All five resident-relay checks succeeded. A different persistent server still needs lifecycle testing because it could share a MIGraphX/runtime defect. Upstream community alternatives include [Dolyfin/parakeet-api-server](https://github.com/Dolyfin/parakeet-api-server) and [PabloBispo/parakeet-local-asr](https://github.com/PabloBispo/parakeet-local-asr). These are candidates, not validated AMD deployments. NVIDIA's [Speech NIM](https://docs.nvidia.com/nim/speech/26.02.0/asr/deploy-asr-models/parakeet-tdt.html) explicitly uses NVIDIA runtime and is not a drop-in Strix Halo solution. No direct server was installed here.

Validation: ten wake unit tests pass, including bytes arriving before endpoint, cancellation closing the relay, bounded transport and existing microphone/call safeguards. Shell syntax and git whitespace checks pass. Worktree only; no fleet activation or main merge.
