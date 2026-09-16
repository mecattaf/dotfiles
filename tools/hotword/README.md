# Zenbook wake-word evaluation

Tom's client is an ASUS Zenbook Duo UX8406MA, Intel Core Ultra 9 185H
(Meteor Lake). The primary goal is fast, reliable wake detection. Low sustained CPU use,
quiet fans on AC power and little maintenance are secondary. Battery endurance is not
an optimization target.

Three separate implementations were measured:

- Scott Baker's existing OpenVINO detector: CPU mel frontend, Intel NPU embedding
  and classifier. Actual Meteor Lake execution succeeded with an isolated Nix
  runtime. Its original Panther Lake/Ubuntu example is a reuse source, not an
  exclusion criterion. See `npu/` for pinned runtime and saved-audio tools.
- Native Sherpa-ONNX keyword spotting: small three-million-parameter streaming
  model, one inference thread, configurable English phrases. Its runner,
  manifest and NAS weights were removed 2026-09-16 (Tom); openWakeWord won.
- Upstream openWakeWord with ONNX Runtime on CPU, explicitly one inference
  thread per session, using the already borrowed Mycroft compatibility models.

The comparison chooses the best complete tool for this laptop. It does not
require matching models or runtimes. Same-code CPU runs may diagnose NPU
problems but do not define the competing CPU implementation. Initial tests
replay saved PCM at its original cadence and run serially on the laptop.
The idle condition is the Niri F10 brightness helper: both panels at brightness
zero, with both displays enabled (DPMS On). It is neither monitor power-off nor
system suspend. The corrected latency fixture starts with 30 seconds of streamed
silence while the detector remains resident; frames become available at their
end, with actual callback timestamps recorded. This is saved-audio timing, not
yet USB-microphone-to-listening-cue timing.
Report startup separately from steady CPU, RSS, frame latency and temperature /
fan RPM. A successful compile or silence test is not a recognition-quality test;
RPM is not an acoustic measurement.

## Models

`manifests/` contains exact source URLs, byte sizes and SHA-256 hashes. Models
are fetched on the NAS by a scoped `LIBRARY_FETCH_MANIFEST` transaction and
explicitly borrowed to `/var/lib/local-models` with `local-models-borrow`.
No ONNX weights belong in the Nix closure. The client has no model-library NFS
mount; this evaluation copied a verified scoped NAS snapshot to
`/var/tmp/mykonos-library-snapshot-20260914` and used it as the explicit borrow
source. The original NAS Library remains canonical.

The openWakeWord Mycroft classifier is a compatibility fixture; it is not Tom's
selected wake phrase. Source runtime and model licenses are separate: consult
the recorded provenance before changing distribution or usage.

## Microphone and call requirements

These tools do not create a listener or open a microphone. Future capture must
use only the USB iContact Camera Pro, never the default source or an internal /
headset fallback. Missing hardware suspends capture and clears buffered audio.

Actual call-recording lifecycle plus a manual call override must inhibit waking.
Both entry and exit clear queued PCM, the ring and detector/VAD state. Rearming
must honor the selected detector's fresh-audio warmup. TTS playback and the
listening cue need explicit inhibition/turn state too. The existing
`speech-listening-cue` package supplies the original entry sound without a daemon.

## Receipts

Research, hardware observations, acquisition receipts and the working experiment
outputs are under `/home/tom/tts-hotword-research-20260914`. Nothing here activates
a NixOS fleet configuration or starts always-on listening. The coordinator/worker
AMD NPU decommission is unrelated and remains in force.
