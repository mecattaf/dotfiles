# Qwen Base: one local voice

**Accepted voice:** Tom listened to the complete midway B reading, called it
“AMAZING” and reported no bang defects. It is now enrolled as the single active
local voice. The original favorite remains available for the exact same-reading
comparison. The earlier expanded-bank demo was rejected after approximately
seven to eight audible bangs; its measurements remain historical evidence.

The voice uses the unmodified Qwen3-TTS 1.7B Base Q8 model through the existing
Vulkan runtime. The coordinator runs inference; the ASUS Zenbook plays returned
PCM through PipeWire. CustomVoice, personality writing and alternate delivery
profiles remain archived experiments.

The accepted identity bank contains 43.42 seconds of source speech plus five
120 ms joins (44.02 seconds total). Six scenes span source time 4.55–164.20:
introduction, probability, occupation, reassurance, unexpected events and final
instructions. The transcript-matched acoustic prefix is 25.20 seconds, including
joins and a 240 ms quiet tail. Source speech remains at its original speed.
This broader reference conditions delivery; it is not model training or a promise
of explicit emotion control.

The complete 344-word reading lasts 115.76 seconds and took 28.81 seconds to
generate (RTF 0.249), in seven deterministic requests. Independent word checks
matched all 344 words. Each chunk starts at zero, and the maximum stitched join
step is one PCM16 unit. No output caps or new kernel errors occurred. Tom's
listening feedback supplies the sound-quality judgment. The original favorite
comparison is `tts-audition-20260914/samples/qwen-guarded-route-long.wav`,
115.68 seconds, with the same text.

## Offline preparation and enrollment

Extraction is setup work. Native cached files can be installed with:

```sh
qwen-speech enroll-latents \
  --speaker /home/tom/tts-base-single-voice-20260914/midway/references/b-identity.spk \
  --codes /home/tom/tts-base-single-voice-20260914/midway/references/b-prefix.rvq \
  --transcript /home/tom/tts-base-single-voice-20260914/midway/references/b-prefix.txt
```

Provenance and input hashes are recorded in
`/home/tom/tts-base-single-voice-20260914/midway/references/provenance.json`.
`midway/activation.json` confirms that the installed profile exactly matches the
tested registration. Enrollment is local runtime state; no fleet configuration
has been activated or merged. The portable comparison is the parent
`listening.html`, copied to the same project folder in the client's Downloads.

Enrollment validates the complete candidate before stopping the service. Under
the synthesis admission lock it preserves the exact old `voice.json` bytes in a
unique `voice-backup-*.json`, then atomically replaces the profile. The profile
and backups are mode 0600 in a mode-0700 state directory. A failed replacement
retains the previous profile. Enrollment takes effect on the next service start;
it does not synthesize a test or modify model weights.

On-demand startup validates the saved profile and posts only native Base fields
(`name`, `spk_b64`, `rvq_b64`, `ref_text`) to `/v1/audio/voices`. The daily path
loads these cached values directly, without reference extraction. Existing WAV
profiles remain supported, as does `qwen-speech enroll REFERENCE.wav TRANSCRIPT.txt`;
that older path performs extraction when the engine starts.

## Native format and bounds

The pinned runtime is ServeurpersoCom/qwentts.cpp revision
`71ad93d591a2811f35db77e27c02acba091c9e9b`. Its
[src/rvq-file.h](https://github.com/ServeurpersoCom/qwentts.cpp/blob/71ad93d591a2811f35db77e27c02acba091c9e9b/src/rvq-file.h)
and [tools/tts-server.cpp](https://github.com/ServeurpersoCom/qwentts.cpp/blob/71ad93d591a2811f35db77e27c02acba091c9e9b/tools/tts-server.cpp)
define the registration format:

- `.spk`: exactly 2,048 finite little-endian float32 values, 8,192 bytes.
- `.rvq`: **no header**. Sixteen codebooks in `[16, T]` row-major order,
  with LSB-first packed 11-bit values. Every decoded value is inherently in
  0–2,047. Exact file length is `22 × T` bytes, with positive `T`.
- A nonempty transcript requires at most 375 frames, or 30 seconds at 12.5 Hz.
  The selected acoustic prefix has 315 frames. This bound applies to the matched
  acoustic/text prefix, not to the audio used to extract the speaker embedding.
- Empty transcript files explicitly select speaker-only conditioning. The server
  still requires an RVQ file during registration but does not pass those codes to
  synthesis when `ref_text` is empty. Such caches remain bounded to 7,500 frames
  (ten minutes); accepting that file size is not a recommendation for long ICL.
- Reference text must be valid UTF-8 without NUL, at most 8,000 characters and
  32,000 bytes. WAV references remain mono 24 kHz PCM16, 2–30 seconds, at most
  8 MiB, with complete PCM and nonempty text. Saved profiles are bounded to
  12 MiB and cannot carry unknown engine fields.

The headerless packed format cannot identify an arbitrary file's intended codec
from its bytes alone. The wrapper enforces this pinned 16-codebook layout; the
model and tokenizer remain the existing loaned Base/12-Hz pair.

## Daily speech and failure handling

Use `speak` with text or `--file`; use `--client client` when invoking playback
from the coordinator. `--output FILE.wav` saves a recording, and `--stop` ends
client playback. The service is on demand and releases the model after its idle
interval. The existing NAS Library and explicit model-loan rules still apply.

Text is partitioned without loss into at most 400-character requests. Each request
has a 512-token output cap (40.96 seconds of PCM); warmup remains 120 tokens.
The cap is an operational guard, not the model's natural maximum duration. A short
written passage with unusually expanded pronunciation can exceed it and must fail
explicitly. A response reaching the cap, an empty/odd PCM chunk, or a response
shorter than its declared HTTP length stops the reading with an error. Failed
recordings remain `.part` files and do not replace a previous successful WAV.
Streaming playback may already have played earlier audio before an error arrives.

The existing guard polls every 100 ms and stops its own engine if AMD device GTT
reaches 64 GiB, available host memory drops below 16 GiB, or counters cannot be
read. Sampling cannot guarantee prevention of every transient allocation failure.
No driver, GPU configuration or model-backbone changes accompany this wrapper.

The expressive wrapper, tests, documentation snapshots and historical Nix paths
are preserved at
`/home/tom/tts-expressive-candidates/qwen-customvoice/archived-wrapper/archive.json`.
The restored Base wrapper came from
`/nix/store/kjsizqb3d9zqf9iclng07zw3bm62sqnc-qwen-speech-0.1.0/lib/qwen-speech.py`.
