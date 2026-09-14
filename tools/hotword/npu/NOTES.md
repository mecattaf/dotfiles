# Scott wake detector: isolated Meteor Lake NixOS test

This is test tooling, not a service or a default microphone listener. Tom authorized reuse of the documented Scott Baker implementation. Do not revive the AMD NPU deployment or install the full browser-chatbot stack.

The `default.nix` runtime builds from pinned Nixpkgs and official Intel userspace compiler assets. It contains **no model weights**. The existing kernel and firmware remain untouched. Models must first arrive through the NAS Library and explicit borrowing; see `../manifests/openwakeword-baker.json`.

Build:

```sh
nix build --impure --file tools/hotword/npu/default.nix --out-link /tmp/scott-npu-runtime
```

`wake-python` supplies OpenVINO2026.3.1, NumPy, NPU UMD1.35.0, LevelZero1.32.0 and the corresponding compiler. Its isolated OpenVINO library layout places the compiler loader beside the NPU plugin, as upstream's plugin compiler expects. `compiler.nix` only extracts and patches userspace libraries from Intel's release archive; it does not run dpkg installation or copy firmware. No globally installed OpenVINO file is modified.

The initial ordinary driver-compiler path enumerated NPU3720 but could not compile the embedding. PLUGIN compiler selection with the isolated layout successfully compiled and executed both Scott's embedding and Mycroft classifier. The mel graph ran CPU with one inference thread. This is a tested configuration, not a claim of universal compatibility across firmware/compiler versions.

In a scratch working directory, `fetch-detector.py` fetches **only** the pinned, SHA-checked `wakeword.py`; it does not clone bundled ONNX models. Place the probe/replay script beside that file. No upstream license file was found at the inspected revision, so preserve attribution and resolve redistribution terms before bundling upstream source in a product. This repository stores the source-fetch recipe rather than the upstream implementation.

Initial tests:

```sh
/tmp/scott-npu-runtime/bin/wake-python probe.py
/tmp/scott-npu-runtime/bin/wake-python test-scott.py \
  --models /var/lib/local-models/openwakeword-baker-compat-v051 \
  --compiler PLUGIN --output compile-silence.json
```

The smoke test uses generated silence and checks execution devices plus reset behavior. The subsequent saved Mycroft positive was accepted three times in three repetitions. It cannot establish keyword recall or household false-activation rate. `replay-scott.py` reads only mono16kPCM16 WAV files and preserves the original80ms cadence. Its wrapper only sets runtime properties and records scores/timing; it does not rewrite the detector algorithm.

```sh
/tmp/scott-npu-runtime/bin/wake-python replay-scott.py \
  --models /var/lib/local-models/openwakeword-baker-compat-v051 \
  --wav /path/to/saved-fixture.wav --seconds 45 --mode npu
```

A classifier needs fresh context after reset. The original resource/smoke positive used five seconds of prepended silence and three seconds of tail per exact upstream utterance. The corrected latency fixture prepends25additional seconds, giving30s continuously streamed initial silence and51.856s total. Its three source intervals end at30.952,39.904,48.856s. Latency tests keep both laptop displays enabled at brightness zero (DPMSOn), not powered off or suspended. Record padding and display checks separately. Production call-entry and call-exit must clear queued PCM/ring/KWS/VAD state. Exit goes through fresh-context warmup before armed; meeting-tail replay is forbidden. These scripts do not implement the future production state machine.

Serialize NPU and CPU thermal windows. Compare this route with the best practical CPU detector, not necessarily the same model. Report saved-fixture detections, process CPU core-share and p95, RSS/PSS, deadlines, temperature and readable fan RPM. Distinguish cold compilation and steady operation; RPM alone is not audible-noise evidence. The laptop stays on AC; battery life is not a ranking objective.

Latency priority now supersedes the initial resource-first selection. Current `replay-scott.py` schedules full chunks at their end, records consumed input end and actual acceptance callback wall time, and accepts `--consecutive 1|2|3` (default3). Do not use the first resource run’s frame-start wall timing as real-time wake latency. Preserve `resource-runner-history.json` and its original receipt source hash. The same source audio can compare relative CPU/NPU acceptance without assuming its file end is the exact phonetic endpoint. No cue is played by this harness.

Completed corrected default-three latency run: three recorded positives accepted, with54 one-second brightness-zero/DPMS-On snapshots including before/after. The following single-frame test stopped before its first phrase when brightness became400; no single-frame timing result exists. Further client tests are paused pending clarification, with no automatic brightness override. No hardware speed winner is established because the matching guarded CPU comparison is also pending. Exact external receipts are under `/home/tom/tts-hotword-research-20260914/compatibility/latency.json`.
