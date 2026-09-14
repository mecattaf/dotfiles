# Native CPU keyword fixture benchmark

This is an isolated Sherpa-ONNX C-API contender for the Zenbook. It does not install a service, open a microphone, play audio, or execute commands. The provisional publisher keyword `LIGHT_UP` checks functionality; it does not select Tom's final wake phrase.

The tested runtime is Sherpa-ONNX1.13.3 with ONNX Runtime1.27.1. The model is the official English/Chinese3M December2025 KWS export: chunk16, INT8 encoder and joiner, FP32 decoder. Configure one inference thread, four active paths, one trailing blank, keyword score1 and threshold0.25. English phrases use the publisher's pronunciation lexicon and matching tokens; unusual names require pronunciation validation. Models remain outside Nix and must come from a verified NAS Library loan.

Build this package with the selected pinned nixpkgs instance:

```nix
pkgs.callPackage ./tools/hotword/cpu/default.nix {}
```

`runner.cpp` receives raw16kHz mono signed16-bit little-endian PCM. It blocks on absolute80ms deadlines rather than spinning. The model's chunk16 encoder has a320ms chunk configuration; that is not a measured phrase-end detection delay. The runner reports steady process CPU time after model initialization, one-second CPU share and p95, processing/decoder p95, scheduling lag, detections, RSS high-water mark and process-wide context-switch deltas. CPU percentages use one logical core as100%, not the whole22-thread host.

`observe.py` is shared with the separate NPU contender. It samples child CPU/RSS/PSS/thread count plus readable temperatures and fan RPM at1Hz. External observer memory peaks include startup; the native runner independently reports steady CPU. `/proc/PID/status` context switches describe only the main thread and are labeled accordingly. Temperature and RPM measurements cannot establish audible quietness. Read-only sensor work and observer CPU are outside the child process's CPU total.

Run `benchmark.py --help` for paths. It runs disabled, saved-audio replay and KWS twice in balanced order, followed by a paced positive fixture. Windows default to60seconds. Disabled is an instrumented sleeping native process with libraries mapped. Replay reads and converts saved PCM; it is not PipeWire capture and does not estimate microphone capture cost. Negative fixtures repeat when exhausted; use sufficiently long recordings when repeats would distort interpretation. The positive fixture should include silence before and after the phrase.

The bounded September2026 run uses one publisher-provided speech positive and saved synthesized negative speech. Those fixtures demonstrate function and resource cost; they cannot establish Tom's recall, a household false-activation rate, or a final winner. No tuning was performed against the measurement windows. Future iContact-only capture, call inhibition, acknowledgement and command routing are separate integration work.

Primary model/API references: [model and keyword instructions](https://k2-fsa.github.io/sherpa/onnx/kws/pretrained_models/index.html), [pinned C API](https://github.com/k2-fsa/sherpa-onnx/blob/v1.13.3/sherpa-onnx/c-api/c-api.h). Source/model provenance and complete measurements are retained in `/home/tom/tts-hotword-research-20260914/cpu-sherpa/`.

## Additional upstream openWakeWord comparator

`openwakeword.nix` packages unchanged openWakeWord v0.6.0 (tag commit
`c8ef6912c5feccf1037b852d9bc6c7ed644135ba`) with single-thread ONNX Runtime CPU
sessions. It does not use Scott Baker's inference implementation. `openwakeword.py`
is only a paced saved-WAV driver with process CPU/resource receipts. It uses the
already Library-managed ONNX mel, embedding, and Mycroft classifier artifacts;
weights are not bundled into Nix. Code is Apache-2.0; pretrained openWakeWord
model licensing is separate (CC-BY-NC-SA-4.0), and this phrase is only a fixture.

Build with the same pinned nixpkgs and `callPackage ./openwakeword.nix {}`.
Run the resulting `openwakeword-fixture --models /var/lib/local-models/openwakeword-baker-compat-v051 --wav SAVED.wav --mode detector --seconds 60`
through `observe.py`. Modes `disabled` and `replay` provide Python harness
baselines. The detector uses 80 ms frames, threshold 0.5 and a fixed 2-second
refractory period. It preserves upstream feature state, fixes its initialization
random seed to 42, disables optional VAD/noise suppression/verifiers, and asserts
CPU execution providers. A refractory period is an event policy, not calibrated
wake-word quality. The driver never captures audio or invokes assistant actions.

For a verified dim-display condition, `observe.py --require-brightness-zero`
checks the Zenbook's two active panel backlights and both eDP DPMS states before
launch, every second, and after exit. It requires0/0 and DPMSOn, saves each check,
and terminates only its own child if the condition changes. This never changes
brightness itself. Other machines need their actual panel paths configured
before using this optional Zenbook-specific guard. One-second sampling does not
exclude shorter changes between samples.
