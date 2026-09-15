# Speech operations

The permanent services have been activated on the fleet. Build, integration and
rollout checkpoints are in `mykonos-overnight-integration.md`. The final machine
receipt is archived at `/mnt/nas/models/research/mykonos/2026-09-14/deployment-receipt.json`;
its revision and service evidence distinguish activation from a build.

## Responsibilities

The Zenbook (`client`) owns the iContact Camera Pro USB microphone, Alexa
openWakeWord detection on CPU, the original listening cue, PCM transport, native
Herdr dictation and speaker playback. It performs no transcription or LLM/TTS
inference. Coordinator owns the resident MIGraphX Parakeet worker, Claude sessions,
the Markdown speech queue and on-demand Vulkan Qwen synthesis.

Parakeet is `istupakov/parakeet-tdt-0.6b-v3-onnx`, revision
`8f23f0c03c8761650bdb5b40aaf3e40d2c15f1ce`, loaded by pinned `parakeet-rs` 0.3.7.
The worker requires MIGraphX rather than silently selecting CPU. It uses a private
Unix socket and one capture at a time. Captures stream over SSH as 16kHz mono
signed PCM; a zero-length frame explicitly commits, while disconnect cancels.
The current capture limit is 60 seconds. This is an intentional intake bound,
not a measured maximum duration of the underlying Parakeet model.

Qwen uses the accepted single midway B K2SO reference: 44.02 seconds of identity
material from six scenes, with a matched 25.20-second prefix. It is still Qwen3-TTS
1.7B Base Q8, not a fine-tuned CustomVoice checkpoint. The accepted derived profile
and its enrollment evidence are a NAS artifact, separate from model weights.
No personality instructions or tone switching are part of this deployment.

## Restore model loans

The canonical Library is on the NAS. Run `library-fetch` there to restore missing
published artifacts, then explicitly run `sudo local-models-borrow --yes` on the
coordinator, whose Library path is the existing NAS mount. This never happens
inside activation or a service startup. Locally imported K2SO material cannot be
re-downloaded: restore it from the NAS archive or backup if missing.

The client has no NAS filesystem mount. To restore its two small wake artifacts,
stage only these canonical directories through the coordinator's NAS mount:

```sh
mkdir -p /tmp/speech-wake-library
ssh coordinator 'tar -C /mnt/nas/models/weights -cf - openwakeword-baker-compat-v051 openwakeword-alexa-v051' |
  tar -C /tmp/speech-wake-library -xf -
sudo env LOCAL_MODELS_LIBRARY=/tmp/speech-wake-library local-models-borrow --yes
```

Run those commands on the client after deploying its declared wanted set. The
borrow transaction verifies the expected file hashes before publishing the loan.
The temporary staging directory can then be removed. NAS Library contents are
never pruned by this workflow. Local pruning is a separate explicit transaction;
no experimental models have been deleted as part of this integration.

## Controls and speech

Alexa opens a new Claude Opus session with a fixed appended system prompt enabling
speech publication. Follow-on hands-free routing to an existing conversation is
not implemented. In a native Herdr projector, hold bare Space for 300ms, wait for
the listening cue, speak, and release. A tap remains a normal Space. Another key,
Escape, focus change, call recording or playback cancels capture. Text is pasted
into the originating pane without Enter. No external recording overlay is used.

Niri Shift+F9 Start recording inhibits the listener and waits for microphone
release. Generic media playback also inhibits listening; only the tagged cue is
exempt. Display brightness and power controls are untouched.

The shared `/speak` skill asks the assistant to atomically publish Markdown in
`~/Speech/intake`. The daemon owns synthesis and playback. Hidden temporary names
must become visible `.md` names when finalized. Working hours are 06:00–24:00,
matching the paper workflow. Outside those hours jobs wait. Receipts, rather than
an assistant's queue-write claim, establish whether playback completed.

## Evidence and history

NAS research archive:
`models/research/mykonos/2026-09-14/voice-investigation.tar.gz`, 6,337 files,
SHA256 `c8d433aeaa782c06e6177f710cd8232d293578f2a41e3f10acdc6570091d305b`.
The original supplied MP3 is archived beside it with its own hash manifest.
Research sources, environments and duplicate weights were excluded; model
artifacts have separate manifests and canonical Library locations.

Earlier Gemma, VibeVoice, CustomVoice, character and Intel NPU documents record
experiments, not active architecture. Gemma E4B/12B remain parked for later audio
research. TTS, ordinary ASR and streaming diarized ASR comparisons are separate.

## Remaining scope (2026-09-15 audit)

The daily path is implemented: Alexa, cue, coordinator Parakeet, a new Claude
Opus session, Markdown speech queue and client Qwen playback. Native Herdr
hold-Space dictation replaces Voxtype. Existing projector processes must be
reopened to load updated client code and command names; the server and PTYs stay.

Open acceptance work: repeat ordinary human speech through the actual webcam
microphone against known text. Clean-file GPU and transport tests pass, but
speaker-to-microphone loopback had poor accuracy and is not human acceptance.

Deferred extensions: hands-free follow-on routing to an existing conversation;
barge-in/echo cancellation while media plays; automatic meeting detection beyond
the integrated call recorder and explicit manual call mode; dictation longer
than the current 60-second capture bound. Media currently inhibits waking, and
Shift+F9 recording has an explicit inhibition handshake. These limits are not
claims about the models' maximum capabilities.

Optional housekeeping: superseded NAS models are retained, not pruned. Gemma
audio and the separate ordinary/streaming VibeVoice ASR tracks remain research,
not services awaiting an automatic promotion. Intel NPU waking was evaluated
and CPU Alexa selected. CustomVoice, tone banks and character/personality work
were explicitly dropped. They are not outstanding implementation commitments.

Operational commands use functional names: `speech-wake`, `speech-dictate`,
`speech-session`, `speech-projector`, `speech-play`, `speech-queue`,
`parakeet-service` and `parakeet-relay`. The corresponding services are
`speech-wake.service` (client), `parakeet-service.service` (coordinator) and
`speech-queue.{service,path,timer}` (coordinator). Historical research paths
retain the location name under which the investigation was originally recorded.
