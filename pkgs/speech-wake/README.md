# Alexa input on the Zenbook

Selected route: upstream openWakeWord on CPU, existing Alexa classifier, and the
original `enter_voice_mode.mp3` listening nudge. The NPU experiment is retained
as research; it is not a dependency. There is no claim that Alexa is universally
the best-trained phrase; it is an available, tested stock model.

`speech-wake --live --once` explicitly opens only the USB iContact Camera Pro.
Say **Alexa**, wait for the short listening cue, then speak one request. After
0.8 seconds of trailing silence the command is sent to the coordinator's existing
`voxtype-relay`. The CLI emits a structured transcript to stdout. It does not type
into windows, execute desktop actions, or submit that transcript to an agent.
Without `--once` it rearms for another request. There is no boot/autostart service.
This is the input integration boundary; agent/action routing remains separate.

The listener stays resident and processes 80 ms frames using single-thread CPU
ONNX sessions. Capture requests 20 ms PipeWire latency (a request, not measured
end-to-end latency). The nudge is launched only after an accepted wake and actual
PCM from the pinned microphone. Cue audio is discarded while the cue plays;
wake inference is suspended throughout command capture/transcription. This first
version expects acknowledge-then-command, not speech overlapping the cue.

Only a uniquely matching iContact node is accepted, by its current object serial.
The capture stream disallows fallback, movement and reconnection. Device loss or
capture failure clears state and retries the same named hardware. It never uses
the default or internal microphone. Command PCM stays in bounded RAM: eight
seconds without speech cancels, thirty seconds total cancels instead of silently
submitting a truncated request. Standard WebRTC VAD supplies speech endpointing.
No passive audio is saved or sent to the coordinator.

## Shift+F9 call recording

The existing Niri Shift+F9 menu invokes `~/.local/bin/call-record`. The updated
helper creates `~/.local/state/speech-wake/call-record` and atomically changes
`epoch` **before either call capture launches**. If a listener owns the runtime
lock, the helper waits for an exact-epoch `ack`, which the listener writes only
after closing capture, stopping its cue/transcription process, clearing buffered
PCM and resetting the detector. Missing acknowledgement prevents call capture
from starting rather than leaving both paths active. A stopped listener needs
no acknowledgement.

While the marker or legacy `call-record/current` exists, the microphone is closed
and no wake/cue is admitted. Stop waits for both recorder processes to end before
changing the epoch again and removing its marker. Exit then starts a fresh capture
and two seconds of fresh model context. Previously queued meeting audio is never
reused. Uncertain cleanup retains inhibition; `call-record recover` requires
checking the remaining capture state. The recorder preserves its original output
and transcription handoff behavior.

`speech-wake --call-mode on|off|status` supplies an independent manual override.
Stopping a call cannot clear that manual override. The held Qwen playback
lock also inhibits the listener; arbitrary audio players do not establish a
playback lease. Browser calls not started by this recorder require manual call
mode. This does not claim automatic identification of every calling application.

## Models, checks and delivery state

Weights are explicit NAS Library loans, never Nix closure or runtime downloads:

- `/var/lib/local-models/openwakeword-baker-compat-v051/`: mel and embedding.
- `/var/lib/local-models/openwakeword-alexa-v051/alexa_v0.1.onnx`: Alexa.

The stock classifier's separate CC-BY-NC-SA-4.0 terms are preserved in the model
provenance. Runtime source is pinned by `tools/hotword/cpu/openwakeword.nix`.

`--fixture FILE.wav` accepts mono PCM16 16 kHz saved audio and exercises the actual
model, fresh-context reset and inhibition checks without microphone or cue.
`tests/speech-wake/test_wake.py` verifies exact device selection, no fallback,
manual/automatic suppression, call-vs-wake races, shutdown-before-ack, and bounded
endpointing. Recorder integration tests independently exercise its lifecycle.

The listener is declared and enabled by `home/speech.nix` on the client.
Live mode verifies the exact `call-record` hook hash before opening a microphone
and refuses to run if the raw checkout and installed package disagree. Deploy
the raw checkout before switching Home Manager. Fixture checks are not a live
microphone or false-activation assessment. See `docs/speech-operations.md` for
current operations and remaining acceptance work.
