# Wake-word implementation on Strix Halo

## Decision

The first real solution on this machine should be a coordinator-only `speech-wake` user service with this pipeline:

```text
PipeWire default source, 16 kHz mono S16
  → 2.5-second RAM ring
  → pyopen-wakeword `hey_jarvis` candidate, CPU
  → sherpa-onnx exact-phrase verifier, CPU
  → acknowledgement chime
  → existing Voxtype/Parakeet command capture
```

This is an implementable awake-workstation design, not a description of Alexa. The detector is cheap keyword spotting, not continuous ASR. It runs only while Linux and the user session are awake; suspend-time wake would require an external always-on satellite.

## Why CPU is the Strix Halo choice

The coordinator already exposes its XDNA2 NPU and gfx1151 Radeon iGPU, but the correct standby target is one Zen 5 CPU thread:

- [`pyopen-wakeword`](https://github.com/rhasspy/pyopen-wakeword) is a precompiled TensorFlow Lite CPU pipeline. The pinned Nixpkgs version is `1.1.0` and includes `hey_jarvis`.
- The packaged [`sherpa-onnx`](https://k2-fsa.github.io/sherpa/onnx/kws/) KWS path uses CPU ONNX Runtime. The pinned Nixpkgs version is `1.13.3`.
- Upstream openWakeWord processes 80 ms frames and reports that one Raspberry Pi 3 core can run roughly 15–20 models in realtime. On the Ryzen AI Max+ 395, one detector and an occasional verifier should be a very small CPU load. That is an inference to measure, not a claimed watt figure.
- AMD’s current Ryzen AI material demonstrates generic ONNX compilation and speech recognition on the NPU, but it supplies no supported openWakeWord or sherpa KWS recipe for Linux Strix Halo. NPU deployment would require graph compatibility work, compilation/cache packaging, and proof that transfers and wake-up overhead do not dominate this tiny batch-one stream. See AMD’s [model deployment path](https://ryzenai.docs.amd.com/en/latest/modelrun.html) and [RyzenAI-SW](https://github.com/amd/RyzenAI-SW).
- The iGPU should remain available for the existing MIGraphX Parakeet path and TTS. Keeping gfx1151 awake for a three-million-parameter standby model has no evidenced advantage.

Revisit XDNA2 only after a seven-day CPU baseline. Promote an NPU build only if it preserves wake accuracy and p95 latency while reducing measured package-power delta materially—30% is a sensible gate. TOPS alone is not evidence.

## Exact components and starting configuration

### Audio owner

One long-lived `pw-record` process targets the stable iContact node already declared in `hosts/coordinator/audio.nix`:

```text
pw-record \
  --target alsa_input.usb-DCX-241206-FAY_iContact_Camera_Pro_01.00.00-02.analog-stereo \
  --rate 16000 \
  --channels 1 \
  --format s16 \
  --raw -
```

PipeWire `1.6.8` is already pinned locally. The supervisor reads the raw stream, divides it into the detector’s required frames, and retains the latest 2.5 seconds in RAM. It never writes standby audio to disk. [`pw-record`/`pw-cat`](https://pipewire.pages.freedesktop.org/pipewire/page_man_pw-cat_1.html) accepts a `node.name` as its target and supports raw PCM. If the named webcam is absent, the service should enter a visible degraded state or explicitly fall back to automatic default selection according to configuration; it must not silently claim to be listening to the preferred route.

The current iContact Camera Pro source is already selected declaratively in `hosts/coordinator/audio.nix`. Before judging KWS accuracy, confirm that its ALSA `Mic Capture Volume` has not returned to zero; the known recovery is `amixer -c Pro sset Mic 36% cap`. An always-on detector makes silent-input health reporting mandatory: expose current RMS, selected node, and time since the last non-silent frame.

### Stage 1: trained candidate detector

Use Nixpkgs `python313Packages.pyopen-wakeword` `1.1.0`, model `Model.HEY_JARVIS`, TFLite CPU. It accepts 16-bit, mono, 16 kHz audio. Start with:

```text
candidate threshold       0.50
consecutive confirmations 2
refractory period         2.0 s
```

The trained `hey_jarvis` model is preferable to running full ASR continuously. Its classifier has already seen synthetic positives, near-homophones, noise, music, podcasts, and reverberation; upstream’s [model description](https://github.com/dscripka/openWakeWord/blob/main/docs/models/hey_jarvis.md) also notes that same-device playback remains a hard case.

### Stage 2: independent exact-phrase verifier

After a candidate, reset a sherpa stream and replay the 2.5-second ring through `sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20`:

```text
model                   chunk-8
encoder and joiner      INT8
decoder                 FP32
provider                CPU
threads                 1
keyword score           1.0
keyword threshold       0.25
accepted keyword        HEY_JARVIS only
```

The model is approximately three million parameters. Its documented chunk-8 algorithmic latency is 160 ms; chunk-16 is 320 ms and can be compared if accuracy is weak. The shipped English lexicon contains `JARVIS`, so the documented `text2token` flow can compile `HEY JARVIS @HEY_JARVIS` without an out-of-vocabulary workaround. See the [exact pretrained model and quantization combinations](https://k2-fsa.github.io/sherpa/onnx/kws/pretrained_models/index.html).

This verifier is invoked only for candidates, so its average standby cost is negligible. It rejects phonetic spikes that survive the first model without requiring a second full ASR instance.

## Service and state machine

Declare a Nix-built `systemd --user` service, parallel to `voxtype.nix`:

```text
Unit:
  After/Wants = pipewire.service wireplumber.service voxtype.service

Service:
  Restart = on-failure
  RuntimeDirectory = speech-agent
  no network access or listening socket
```

Its operational states are:

```text
MUTED
  └─ explicit enable → STANDBY

STANDBY
  pw-record + 2.5 s ring + openWakeWord
  └─ candidate → VERIFY

VERIFY
  replay ring to sherpa
  ├─ reject → reset detectors → STANDBY
  └─ exact match → ACK

ACK
  freeze ordinary wake acceptance, play local chime
  └─ start Voxtype file capture → COMMAND

COMMAND
  wait for speech; endpoint after trailing silence
  ├─ no speech for 5 s → cancel → STANDBY
  ├─ hard limit 30 s → stop
  └─ 800 ms trailing silence → stop Voxtype → AGENT

AGENT
  wait for authoritative transcript file, dispatch to speech-loop/Pi
  └─ response clauses → TTS → SPEAKING

SPEAKING
  suppress ordinary wake acceptance
  allow explicit stop/cancel path
  └─ playback complete + 500 ms cooldown → STANDBY
```

The supervisor publishes state, selected source, score, and timing events to a private runtime socket or status file so a Niri/Waybar indicator can distinguish standby, verifying, recording, thinking, and speaking.

## The integration that works today

Voxtype `0.7.5` already supports external control:

```text
voxtype record start --file=/run/user/$UID/speech-agent/turn.txt
voxtype record stop
voxtype record cancel
```

This reuses the resident `parakeet-unified-en-0.6b` ONNX/MIGraphX service declared in `home/voxtype.nix`, including its true cached streaming configuration. It does not load another Parakeet model or adopt the batch/progressive decoder from the Hugging Face demo.

The reliable first interaction is deliberately two-stage:

```text
Tom:     “Hey Jarvis”
machine: [chime]
Tom:     “Read the current report.”
```

The supervisor calls `record start --file=...` immediately before the chime completes, owns endpoint timing, calls `record stop`, and waits for a non-empty final transcript. The chime is both feedback and a clean boundary that prevents the first command word from being lost.

## Why one-breath input needs one code change

This form is not lossless with the current CLI:

```text
“Hey Jarvis, read the current report.”
```

Voxtype opens its own microphone after `record start`; it cannot consume the wake supervisor’s pre-roll. The first command word may already be in the 2.5-second ring before Voxtype starts. Running `voxtype transcribe` on a WAV is not a good fix because it bypasses the resident daemon and creates a second ASR lifecycle.

The durable one-breath design is:

1. `speech-wake` becomes the sole PipeWire capture owner.
2. Voxtype gains a daemon IPC/FD operation: `begin external turn`, raw 16 kHz mono S16 frames, then `end` or `cancel`, plus an output target.
3. Sherpa’s wake timestamps identify the wake-word end.
4. The supervisor discards audio through that boundary and feeds buffered post-wake samples plus live frames into the resident Parakeet streaming session.

The existing 2.5-second ring is sufficient. Until that raw-PCM ingress exists, retain the honest chime-then-command UX.

## Stopping and barge-in

Room-speaker full duplex is not part of this first service. While local TTS plays, normal `hey_jarvis` acceptance is inhibited so the assistant cannot summon itself. Provide an independent stop path first: keyboard/button cancellation and, if hands-free stop is required, a narrowly trained `stop` detector operating against a PipeWire echo-cancelled source.

Natural speech-over-speech interruption requires an acoustic echo-cancel reference containing the exact playback samples. That belongs in the later `speech-loop`/WebRTC phase, not in the wake service.

## Acceptance gates

Run the iContact/GS3 far-field and INZONE headset routes separately:

| Gate | Promotion target |
|---|---|
| Deliberate wake acceptance | At least 95 of 100 across distance, angle, normal/quiet voice, fan and music |
| Wake latency | p95 phrase-end to chime at or below 500 ms; verifier never blocks over 750 ms |
| Command boundary | 50 chime-separated commands per route with zero clipped first words and zero premature stops |
| Dark run | Seven days with zero post-verifier false activations |
| Idle resources | Under 5% of one logical CPU, RSS under 250 MiB, median package-power delta under 1 W |
| Recovery | Unplug/replug, default-route change, lock, suspend/resume, Voxtype restart, and TTS cooldown all return to standby |

The resource numbers are gates, not measurements already achieved. Log scores and timing by default, not raw audio. During a short explicit calibration window, test podcasts, films, music, the eventual assistant voice, actual “Hey Jarvis” media, and near-homophones. Exact external speech of the phrase is a genuine match; the second stage cannot magically know whom it was addressed to.

## Custom phrase path

The MVP needs no training. Sherpa can trial arbitrary typed phrases immediately. If a private phrase proves substantially more reliable, train a dedicated openWakeWord model and retain sherpa as the exact-phrase verifier. LiveKit’s newer [`livekit-wakeword`](https://github.com/livekit/livekit-wakeword) provides a reproducible synthetic-data, augmentation, export, and DET/FPPH evaluation pipeline, but its runtime/training surface is newer and not needed to ship `hey_jarvis` first.

The first implementation decision is therefore complete: CPU OpenWakeWord candidate, CPU sherpa verifier, exact PipeWire source, two-stage Voxtype bridge, and measured promotion gates. XDNA2 remains an evidence-driven optimization experiment rather than a prerequisite.
