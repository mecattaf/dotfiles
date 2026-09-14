# Local speech comparison — 14 September 2026

**Latest voice decision:** Tom accepted the cleaned midway B reference after listening and reported no bangs. It is enrolled locally as the single Qwen Base voice. The exact original favorite below remains the historical baseline. See [the accepted recipe](qwen-base-single-voice.md) for the current 44.02-second identity bank, 25.20-second prefix and enrollment receipt. The model/provider and separate ASR conclusions below are unchanged.

Worktree: `~/mecattaf/dotfiles-qwen-tts-zenbook`, branch `work/qwen-tts-zenbook`.
All model inference runs on the coordinator (Ryzen AI MAX+ 395, Radeon 8060S, 128 GB). The Zenbook is the playback client. The three tracks are evaluated separately: TTS, ordinary VibeVoice transcription, and the new streaming ASR. Qwen through the upstream qwentts.cpp runtime is the clear TTS leader so far; voice and precision refinements remain open. Relative artifact paths below refer to the audition directory `~/tts-audition-20260914/` or the matching portable review bundle. The liked live voice is preserved in `liked-baseline.json` and `liked-baseline-voice.json`.

**Listening preference update:** Tom explicitly preferred “Qwen · complete stitched WAV received by Zenbook” (`samples/qwen-guarded-route-long.wav`, 115.68 seconds). Preserve Qwen 1.7B Base Q8, the 8.75-second raw K-2SO intro and deterministic 400-character chunks as the preferred baseline. Breath filtering remains off. Tom also preferred the 76.96-second one-shot size-sweep recording (`benchmarks/qwen-length-sweep/limit-1600.wav`), using the same model/reference. Both are listening favorites; this does not by itself choose a new chunk-size policy. Exact waveform/configuration evidence is in `preferred-sample.json`.

## TTS selection table — speed and quality kept separate

“Provider” below means the local inference implementation. All run on the same coordinator. Smaller RTF is faster; **process** RTF includes loading/reference preparation, while **resident** RTF excludes that one-time work. Compare matching timing columns.

| Inference implementation / model | Short process RTF | Short resident RTF | Long complete-reading RTF | First delivered audio | Quality evidence / audition |
| --- | ---: | ---: | ---: | --- | --- |
| **qwentts.cpp / Qwen 1.7B Q8** | 0.415–0.458 | **0.249–0.264** | **0.243–0.249**, chunked | Warm 63–65 ms after readiness | User-liked K-2SO reference; all three long readings 344/344 words; raw/light/Demucs and generic voices available |
| **qwentts.cpp / Qwen 0.6B Q8** | **0.330–0.354** | Not measured | Not measured | Not measured | Fastest matched fresh-process Qwen control; short wording differs only by contraction; listen for identity/prosody tradeoff |
| qwentts.cpp / Qwen 1.7B BF16 | 0.667–0.690 | Not measured | Not measured | Not measured | Higher stored weight precision; short wording differs only by contraction; quality benefit not established |
| Khimaros / Qwen 1.7B Q8 | 3.006–3.050 | Not measured | Not measured | Not measured | Raw/light/Demucs clone recordings; matching format/codec differs from qwentts.cpp |
| C++ VibeVoice Realtime 0.5B Q8 | See receipts | About 0.42 | 0.418 | 342 ms callback, plus load | Carter generic voice, not raw K-2SO enrollment; complete long reading with three strict transcript edits |
| C++ VibeVoice 1.5B Q8 clone | See receipts | 1.10–1.17 | **Failed completeness** | Batch WAV; short generation about 10 s | Exact short wording; long memory failure, then omissions despite guarded chunking |
| Recovered VibeVoice Large / Python SDPA | See receipts | 1.76–1.86 | 1.824, one shot | Batch WAV | Exact short and full 344-word long wording; larger historical raw-reference cloning control |

**Fastest tested implementation:** qwentts.cpp. **Fastest matched short-process model:** its 0.6B Q8 control. **Best-supported deployment baseline so far:** its 1.7B Q8 path, because it combines the liked voice with complete repeated long readings and low delivery latency. The final model-size/precision choice should follow listening as well as speed. Word recognition is not a perceptual-quality or speaker-similarity score.

## Track 1 — TTS comparison

RTF is generation wall time divided by generated audio duration; below 1 is faster than real time. These resident benchmarks separate loading from synthesis, retaining the same loaded model for three requests. A fresh process still benefits from existing operating-system file and shader caches: these are not first-ever installation timings.

| Runtime / workload | Load + enrollment, s | Generation runs 1 / 2 / 3, s | Audio runs 1 / 2 / 3, s | RTF runs 1 / 2 / 3 |
| --- | ---: | --- | --- | --- |
| qwen-serveurperso-short | 1.35 | 2.18, 2.00, 2.15 | 8.24, 8.00, 8.64 | 0.264, 0.250, 0.249 |
| qwen-serveurperso-long-chunked | 1.29 | 28.07, 29.44, 28.38 | 115.04, 118.08, 116.80 | 0.244, 0.249, 0.243 |
| VibeVoice Large / eager | 4.55 | 19.53, 19.76, 19.15 | 10.27, 10.27, 10.27 | 1.903, 1.924, 1.865 |
| VibeVoice Large / sdpa | 5.95 | 20.59, 19.49, 19.58 | 11.07, 11.07, 11.07 | 1.861, 1.761, 1.769 |

The short input is the same 27-word, 152-character assistant acknowledgment across the TTS comparisons. The long input is an original 344-word, 2,207-character passage in `long-comparison.txt`, not the article's unavailable Jevons benchmark text. All three chunked Qwen long outputs passed independent CPU Parakeet transcription with zero normalized word errors and their final sentence intact. Fixed seed 42 did not produce identical Qwen waveforms across requests: the output hashes and durations differ.

The short Qwen HTTP benchmark records warm first-PCM arrival at about 63–65 ms. Long reading warm first-PCM arrival is about 65–70 ms. These are coordinator delivery timings, not acoustic latency at the laptop. The separately verified SSH/PipeWire route logged 65 ms to first PCM after readiness. End-to-end first sound also includes service startup, SSH, buffering and the selected audio device. The first sample the user liked was a live utterance; the matched comparison recording reuses its exact reference/profile but speaks the standardized text.

For a matched CLI-to-CLI comparison, both Qwen packages were also run three times from separate processes, with the same original reference, input and seed. Every invocation includes model loading and reference encoding; operating-system/shader caches remain available.

| Runtime | Process time runs 1 / 2 / 3, s | Audio runs 1 / 2 / 3, s | Process RTF runs 1 / 2 / 3 |
| --- | --- | --- | --- |
| Qwen / qwentts.cpp | 3.42, 3.67, 3.77 | 8.24, 8.24, 8.24 | 0.415, 0.445, 0.458 |
| Qwen / Khimaros | 24.60, 24.50, 24.85 | 8.15, 8.15, 8.15 | 3.019, 3.006, 3.050 |

Khimaros uses a different GGUF conversion and matching F16 codec. Its internal reported total excludes some reference preparation, so process timing is the safer comparison. Both logs explicitly select the Radeon Vulkan backend. They are distinct upstream implementations of the same model family, not identical kernels or interchangeable model files.

Sampled CLI process-tree RSS peaks were about 2.95 GB for qwentts.cpp and 1.20 GB for Khimaros; corresponding device GTT peaks were about 4.70 GB and 4.81 GB. The lower Khimaros RSS does not imply lower total device memory. These are overlapping process/driver views on unified memory.

### Long-input boundary that affects architecture

A single 2,207-character HTTP request with a generous token cap did not complete. The upstream server aborted at `decode would overflow cache (4097 > 4096)` after 3,976 frames. That run is a failure, excluded from speed comparisons; its logs remain in `benchmarks/qwen-serveurperso-long/`.

The implemented relay already splits input losslessly into at most 400-character requests. Testing that actual boundary produced three complete 115–118-second readings at about 0.24–0.25 RTF. This establishes the measured chunked path, not unrestricted one-shot long-form support. Seam quality and long listening comfort still need human listening. This is sequential text chunking under one resident model, not concurrent GPU batching. The 400-character cap is a validated operating point, not a claim that we located an exact universal performance cliff. The supplied input is divided before synthesis, so long requests cannot silently grow into the failing one-shot path. Per-chunk time, characters and audio duration are retained in every long benchmark receipt.

The corrected Python Large long run loaded in 5.33 seconds and generated 168 seconds of audio in 306.37 seconds (1.824 generation RTF). It stopped naturally at 1,270 steps, below the effective 4,096-step cap. Peak active Torch allocation was 19.04 GB. The full parsed input is verified before inference; segmented CPU validation recovered all 344 words with zero edits, four exact overlap joins, and the final sentence intact. The five raw transcription windows and joins are retained under `k2so/analysis/vibevoice-large-long-final/`. This is one full long take, while the short suites have three resident repeats.

### Current C++ VibeVoice TTS

These are two different checkpoints in the same C++ engine. Realtime 0.5B uses the published Carter voice prompt; the 1.5B model accepts the same raw K-2SO reference used for Qwen.

| Model / voice | Load, s | Generation, s | Audio, s | Generation RTF |
| --- | ---: | --- | ---: | --- |
| Realtime 0.5B Q8 / Carter, three resident short takes | 0.64 | 4.53 / 4.40 / 4.52 | 10.67 each | about 0.42 |
| Realtime 0.5B Q8 / Carter, one long take | 0.49 | 53.90 | 129.07 | 0.418 |
| 1.5B Q8 / K-2SO, three resident short takes | 1.36 | 9.95 / 10.15 / 10.63 | 9.07 each | 1.10 / 1.12 / 1.17 |

The Realtime C API's first PCM callback arrived at **342 ms**, after a separate 477 ms load, delivering an initial 800 ms audio block. The callback recording and all three batch short recordings had identical PCM hashes. This confirms streaming on the tested short request; long streaming callback timing was not measured. Carter's long recording reaches the ending, with three strict transcript edits out of 344 words, including one spelling variant. The K-2SO short clone passes all 27 words, and all three takes have identical PCM hashes at seed 42.

An unrestricted 1.5B cloned long request **failed**: RADV exhausted memory during command submission, followed by a device-lost exception after 158.67 seconds. Driver GTT peaked at **127.03 GB**; no completed audio is claimed. The process exited, memory returned to baseline, and both ordinary ASR fixtures subsequently passed without a device reset. The C++ clone's acoustic decoder processes the full accumulated sequence, whereas Realtime uses small windows; this is a plausible memory explanation from the source, not a profiler-confirmed attribution. The failure belongs specifically to the 1.5B TTS path.

A guarded long comparison used the same seven lossless 400-character chunks as Qwen, with termination at 80 GB sampled device GTT. It completed allocation safely and returned to about 8.19 GB GTT after each chunk, but omitted requested speech. Its 126.72-second synthesis / 124.13-second output is therefore **not a valid complete-reading speed result**. Individual chunk transcripts find 54 edits across 344 requested words (15.70%), including true omissions in chunk four and garbled openings later. A whole-file recognizer dropped some intact speech, so its higher aggregate error is discarded. Individual chunk transcripts and the failed reading remain available as failure evidence. Chunking solves the observed memory pressure for this fixture, but has not established reliable full-content cloning.

### Continuous audio and deterministic chunking

The table distinguishes **the longest complete single request tested here** from a mathematical or advertised ceiling. There is no universal maximum number of seconds: prompt length, speaking rate, generation limits, model behavior and memory all matter. We did not run every model to exhaustion to invent a precise cliff.

| Model / implementation | Longest complete one-shot output verified here | Relevant boundary / decision |
| --- | ---: | --- |
| Qwen 1.7B Q8 / qwentts.cpp | **76.96 s**, 1,466 actual characters, 228/228 words | Larger 2,207-character unrestricted attempt failed; deploy deterministic chunks at 400 characters |
| Qwen 0.6B Q8 / qwentts.cpp | 8.24 s short control | Long one-shot limit not measured; same relay chunking available |
| Qwen 1.7B BF16 / qwentts.cpp | 8.80 s short control | Long one-shot limit not measured; same relay chunking available |
| Qwen 1.7B Q8 / Khimaros | About 9.03 s short control | Long one-shot limit not measured |
| Recovered VibeVoice Large / Python SDPA | **168.00 s**, 344/344 words | Effective generation cap explicitly raised; one-shot succeeded, no maximum established |
| VibeVoice Realtime 0.5B / C++ Carter | **129.07 s**, complete ending with three strict transcript edits | Tested frame cap 1,800; no maximum established |
| VibeVoice 1.5B / C++ clone | **25.87 s**, first standalone chunk, 64/64 words | Whole long request exhausted memory; safe-memory chunking still omitted text, so no reliable long-clone deployment |

The Qwen single-request sweep used sentence/paragraph boundaries, so actual inputs were smaller than their nominal size limits:

| Actual characters / words | Continuous audio, s | Generation, s | RTF | Word check |
| --- | ---: | ---: | ---: | --- |
| 386 / 64 | 21.28 | 5.16 | 0.243 | 64/64 |
| 794 / 128 | 42.48 | 10.32 | 0.243 | 128/128 |
| 1,025 / 164 | 49.60 | 12.08 | 0.244 | 164/164 |
| 1,466 / 228 | 76.96 | 18.92 | 0.246 | 228/228 |

No meaningful throughput cliff appeared across this sweep. The 400-character deployment cap is deliberately below the largest verified one-shot input; it is a stable operating choice, not an asserted model maximum. Every sweep transcript was checked with resolved segment overlaps. The engine's talker cache has 4,096 positions including prompt/context. Its tokenizer runs at 12.5 frames per second despite the “12Hz” name; our 2,048-frame request cap permits at most roughly 163.84 seconds of generated frames, **not a promise of that much complete, coherent speech**. The smaller CLI controls used 900 frames, about 72 seconds of budget, but only short text was tested. VibeVoice's 3,200-sample frames at 24 kHz are 7.5 Hz; the C++ long-test cap of 1,800 frames is 240 seconds of budget, not a validated maximum. [Pinned Qwen implementation](https://github.com/ServeurpersoCom/qwentts.cpp/tree/71ad93d591a2811f35db77e27c02acba091c9e9b/src), [pinned C++ VibeVoice implementation](https://github.com/localai-org/vibevoice.cpp/tree/000e37282bc5bb09edc20f7047a47924122ba3a0/src).

The production stitching rule is simple: take at most 400 characters, prefer the last sentence or paragraph boundary, otherwise the last whitespace boundary, otherwise cut at 400; preserve every character in the partition. Render those chunks sequentially through the same resident voice. Append the resulting mono 24 kHz signed-16-bit PCM in order, with **no crossfade or inserted silence**, then finalize a single WAV. A failed response leaves a `.part` file and a failure exit code. The text boundaries and stitching are deterministic; GPU/model sampling does not guarantee identical waveforms between runs. Existing natural pauses remain in each generated chunk. The final file can be much longer than one chunk; the tested whole reading is about two minutes.

### Voice comparison

**Yes: the supplied MP3 was enough to produce usable cloned voices.** The exact reference behind the live sample you liked is only 8.75 seconds long (the “nine-second intro”), from source timestamps 4.55–13.30 seconds. Both Qwen and the tested VibeVoice cloning paths generated new wording from it. This establishes successful reference-conditioned synthesis, not a quantified Tudyk identity match. The sample includes the film character’s processing and background sound, which is why clean/raw comparisons matter.

The original downloaded MP3 is unchanged. `k2so/manifest.json` records source timestamps, exact transcripts, transforms and hashes. The bank has raw, light-cleaned and CPU-Demucs-separated clips, including intro references of different lengths and a disjoint holdout. Seven references were auditioned with Qwen; the raw/light/Demucs intro was also compared with Khimaros. Preserve all variants: removing background music can also remove useful vocal texture.

Three original male alternatives were designed with Qwen VoiceDesign, then rendered by Qwen Base: **precise companion**, **warm steward**, and **dry analyst**. Their prompts and seed recordings remain in `generic/`. These are designed alternatives, not claims that an official preset reproduces Alfred, Jarvis or Tudyk. The current preference remains the user-liked K-2SO baseline. For a generic alternative, start listening with **precise companion** (calm, precise contemporary British direction), followed by **warm steward** (older Alfred direction). Those are prompt directions, not claims of achieved actor resemblance. The source-backed preset/design research is in `generic-voice-research.md`.

Independent ASR checks find wording errors and omissions; they do not measure voice identity, humor, warmth or listening comfort. Some strict WER differences are contractions such as “I'm” versus “I am.” VibeVoice Large's initial eager sample was transcribed with “run locally” instead of “running locally.” Keep the audio as the authority when the recognizer is uncertain.

### Model size and precision controls

The same qwentts.cpp build also ran three CLI requests for 0.6B Base Q8 and 1.7B Base BF16, using the same original intro reference and F32 codec. These are complete-process timings, including loading and reference preparation.

| Talker checkpoint | Process time runs 1 / 2 / 3, s | Process RTF runs 1 / 2 / 3 | Peak device GTT, GB |
| --- | --- | --- | ---: |
| 0.6B Base Q8 | 2.92, 2.72, 2.72 | 0.354, 0.330, 0.330 | 3.61 |
| 1.7B Base Q8 | 3.42, 3.67, 3.77 | 0.415, 0.445, 0.458 | 4.70 |
| 1.7B Base BF16 | 6.02, 5.87, 6.07 | 0.684, 0.667, 0.690 | 6.56 |

The smaller model is quicker; the BF16 checkpoint costs more time and memory. Both additional control recordings were recognized with only an “I am”/“I'm” contraction difference. That does not establish a voice-quality winner. The BF16 label describes stored talker weights: it does not mean every Vulkan operation executes native BF16 arithmetic. The source converts selected convolution weights to supported types; no blanket precision/throughput claim is inferred.

## Track 2 — Ordinary VibeVoice transcription

This track tests complete-recording transcription with speaker labels and timestamps, using the current C++ implementation and its published **ASR 7B Q4_K** GGUF. It is independent of TTS and of the September streaming checkpoint.

| Controlled input | First request, s | Resident repeat, s | Warm RTF | Content result | Speaker result |
| --- | ---: | ---: | ---: | --- | --- |
| 27.32 s A–B–A fixture | 7.09 | 6.46 | 0.236 | 81/81 words, both runs | 0 → 1 → 0 |
| 115.04 s technical reading | 24.06 | 23.09 | 0.201 | 344/344 words, both runs | One speaker throughout |

Loading was 3.59 s for the short suite and 3.51 s for the long suite, outside request timings. The first result is returned after processing the complete recording. The raw output contains Start, End, Speaker and Content fields. Word/speaker evaluation passed; timestamp-based diarization error was not measured. The A–B–A fixture has two known generated male voices with identical spoken wording, separated into three turns. It is useful for controlled reidentification, not a general real-call accuracy estimate.

The ordinary model is useful on its own merits: exact wording on both controlled recordings, speaker attribution and structured timestamps. Its implementation predates the new streaming checkpoint; that chronology does not make this complete-recording path invalid or superseded. In separate phase-metered resource runs, model-load GTT peaked at 12.60 GB; short and long inference peaked at 25.82 and 26.89 GB respectively. Mean inference APU PPT was 68.3 W and 73.2 W. Process RSS was only about 0.15–0.22 GB during inference, illustrating why RSS alone badly understates this Vulkan workload. Those resource runs also passed 81/81 and 344/344 words.

## Track 3 — New VibeVoice streaming transcription

The September 3 model uses the actual incremental API: encode one available window, then generate that window's text. The upstream full-file iterator pre-encodes the whole recording before yielding, so it was not used to claim live-input latency.

### Streaming 1.5B

| Controlled input | First request, s | Warm requests, s | Warm compute RTF | Content result |
| --- | ---: | --- | ---: | --- |
| 27.32 s A–B–A fixture | 4.46 | 3.38, 3.38 | 0.124 | 81/81 words; speaker 0 → 1 → 0 |
| 115.04 s technical reading | 14.94 | 13.50 | 0.117 | 7 edits / 344 words in both runs; one speaker |

The long-reading edits include **seconds → milliseconds**, **kernels → signals**, and **tensors → tenses**. Both CPU Parakeet and ordinary C++ VibeVoice ASR recovered the original wording on this recording. The streaming 1.5B result therefore cannot be described as verbatim technical transcription merely because the short fixture was perfect.

The checkpoint requires **2.933 s of audio per chunk plus 0.533 s lookahead**. During actual paced replay, its first completed text chunk arrived **4.453 s after audio began**: 3.467 s required audio plus 0.986 s compute. Prompt initialization was a separate 0.302 s and loading another 1.287 s. The final word arrived at 27.494 s, about 0.174 s after the recording ended. Subsequent window compute was 0.174–0.399 s. Warm first-window compute implies approximately 3.86 s live latency, but that is an estimate, distinct from the measured paced run.

The model emits `Speaker N:` lines and continuation text. Its output is speaker-attributed; it does not supply precise word or speaker timestamps in this tested API. No timestamp DER is claimed. Microsoft describes the released checkpoints as targeting recordings up to eight minutes, retaining previous speech/text context without compression; this 115-second test does not establish hour-long meeting support. A disjoint 24.31 s movie-audio probe showed conspicuous phrase/name disagreements; without manually verified gold transcription and speaker timing, it is retained as an unscored robustness probe.

Across the measured 1.5B suite, peak active Torch allocation was about 5.36 GB, reserved space about 5.59 GB, driver GTT about 6.03 GB, and warm process RSS about 2.32 GB. These overlap. Unpaced warm processing sampled about 81–83 W APU PPT; paced replay averaged about 20.6 W while frequently waiting for input. This difference illustrates why offline throughput and a live stream need separate resource measurements.

### Streaming 7B capacity control

The official 7B checkpoint was tested with the same recordings, seed, decoding settings and chunk/lookahead contract. It contains 8.674 billion total parameters including speech components, versus 2.814 billion in the nominal 1.5B checkpoint. Both use BF16 weights and the same pinned Python/ROCm stack.

| Controlled input | First request, s | Resident repeats, s | Compute RTF | Wording | Speaker result |
| --- | ---: | --- | ---: | --- | --- |
| 27.32 s A–B–A fixture | 10.88 | 10.03, 10.03 | 0.398 first; 0.367 warm | 81/81 words, every run | **All three turns labeled Speaker 0** |
| 115.04 s technical reading | 42.04 | 42.12 | 0.365–0.366 | One US/UK spelling disagreement / 344 words, both runs | One speaker |

Loading the resident suite took 4.92 seconds, separately. The lone long-text difference was “acknowledgments” versus “acknowledgements”: strict WER 0.29%, without the substantive terminology substitutions found in 1.5B. However, speaker separation failed on every short fixture run, including paced replay. After optimal mapping, 54/81 words receive the expected speaker identity (66.7%); this is word-aligned attribution, not timestamp DER. The two generated voices are a small controlled test, not a general ranking of real-call diarization.

Actual paced 7B replay delivered first text at **5.359 seconds** after audio began and the final text at **28.445 seconds**, 1.125 seconds after the 27.32-second input ended. Its 3.34-second model load and about 0.358-second prompt initialization are outside those replay-relative times. The fixed 3.467-second required audio window remains. Peak active Torch allocation was 17.65 GB, reserved space 17.82 GB, and device GTT 18.20 GB; warm process RSS was about 2.32 GB. Unpaced long inference averaged 72.4–74.1 W APU PPT; paced inference averaged 31.7 W.

Both 7B phases ran with an 80 GB GTT emergency guard, which never triggered. The saved kernel-journal cursor audit found **zero new kernel records or GPU errors** during these phases.

**Streaming conclusion:** 1.5B is faster and separated the controlled speakers; 7B recovered technical wording more faithfully but merged the speakers. Neither dominates both jobs. The larger-capacity control prevents attributing the smaller model’s wording errors to streaming alone. For complete recordings, ordinary C++ ASR remains the stronger tested combination of exact words, speaker labels, timestamps and throughput. For incremental use, the 1.5B and 7B tradeoff remains explicit. Neither replaces the existing transcription route on the strength of this small synthetic test alone.

## Version and model lineage

| Implementation / model | Pinned version or date | Meaning |
| --- | --- | --- |
| Serveurperso Qwen C++ | `71ad93d591a2811f35db77e27c02acba091c9e9b`, September 14 | Current tested Qwen3-TTS Base/VoiceDesign Vulkan implementation |
| Khimaros Qwen C++ | `0c8b2ba0e7c57a2741852f4305a92996258a71a0`, June 16 | Separate tested implementation and GGUF/codec format |
| Legacy VibeVoice Large Python | Kyuz0 `c9a724f6ddb66c3c1cd89d5038ce084cdb8e1766`, September 13, 2025 | Recovered older 7B-backbone TTS with raw-reference cloning |
| VibeVoice C++ | localai-org `000e37282bc5bb09edc20f7047a47924122ba3a0`, July 9, 2026 | Newer C++ engine; different TTS and ASR model paths |
| Microsoft ASR-Streaming | Released September 3, 2026 | New speaker-attributed streaming ASR; separate from Realtime TTS |

VibeVoice uses a Qwen2.5 language backbone combined with trained speech encoders/decoders and, for TTS, a diffusion head. It does not invoke a separate Qwen2.5 assistant service. The existing assistant LLM can remain unchanged. The checkpoint cannot become Qwen3 merely by changing its tokenizer or loading a newer C++ runtime. Qwen3-TTS is a distinct speech family. [VibeVoice overview](https://github.com/microsoft/VibeVoice), [Realtime model card](https://huggingface.co/microsoft/VibeVoice-Realtime-0.5B), [1.5B model card](https://huggingface.co/microsoft/VibeVoice-1.5B).

The requested mudler repository now redirects to localai-org. Its current C++ source has July 9 PCM streaming callbacks for **Realtime 0.5B**, newer than the pasted post's “no streaming” limitation. The CLI still returns a complete WAV. The **1.5B** C++ path accepts a raw reference WAV; the Realtime checkpoint omits the enrollment encoders and uses preconverted voice prompts. The bundled Carter prompt is a generic control, not a new K-2SO clone. Its ordinary **7B ASR** is also separate from Microsoft's September streaming ASR. [Current C++ source](https://github.com/localai-org/vibevoice.cpp), [streaming change](https://github.com/localai-org/vibevoice.cpp/commit/000e37282bc5bb09edc20f7047a47924122ba3a0).

Microsoft removed the original TTS code in September 2025; the recovered Large fork is therefore a historical quality/control comparison. Current ASR and Realtime releases remain different supported branches of the model family. Source dates, weight revisions and successful local tests are reported separately; neither a recent README nor the old “Qwen2.5” name alone proves suitability.

## Resource comparison

These decimal-GB figures are sampled peaks on this machine, not model-file sizes. Phase-specific measurements are explicitly distinguished from whole-process measurements.

| Runtime / measured workload | Driver GTT peak, GB | Process RSS peak, GB | Mean APU PPT, W | Scope |
| --- | ---: | ---: | ---: | --- |
| Qwen 1.7B Q8 / long chunked | 3.81 | 2.94 | 66.6 | First resident request |
| Khimaros 1.7B Q8 / short | 4.81 | 1.20 | See receipts | Fresh CLI processes |
| VibeVoice Large / SDPA short suite | 19.49 | 2.94 | 66.0 | Whole process, load plus three requests |
| C++ Realtime 0.5B / Carter long | 3.08 | 0.37 | 56.4 | Whole process, load plus one request |
| C++ 1.5B / cloned short | 19.69 | 0.16 | 59.9 | First inference phase; load measured separately |
| C++ 1.5B / unrestricted cloned long failure | 127.03 | 1.03 | Excluded | Failed before producing complete audio |
| Ordinary C++ ASR 7B / long | 26.89 | 0.22 | 73.2 | Inference phase |
| Streaming ASR 1.5B / warm short | 5.99 | 2.34 | 81.7–83.4 | Unpaced inference |
| Streaming ASR 1.5B / paced short | About 6 | See receipts | 20.6 | Includes waiting for live input |
| Streaming ASR 7B / long | 18.20 | 2.32 | 72.4–74.1 | Unpaced inference |
| Streaming ASR 7B / paced short | 18.17 | 2.29 | 31.7 | Includes waiting for live input |

## Measurement boundaries

`tools/qwen-tts/measure.py` samples process-tree RSS, CPU time and the coordinator's AMD driver counters every 100 ms. GPU busy%, VRAM and GTT are device-wide counters. PyTorch allocation and reservation figures are recorded separately when exposed. On unified memory these overlap: never sum RSS+GTT+VRAM+PyTorch to claim a total. Peaks can miss shorter transients.

The power source is the APU **PPT** sensor. Some takes overlapped authorized NAS transfers or short CPU transcript checks; package power includes that background activity. Its integrated joules and average watts are not whole-system wall electricity measurements, so no household cost estimate is inferred. GPU inference jobs are serialized; model transfers and short CPU transcript checks can run concurrently. There is no claimed profiler attribution for every timing difference, and selecting SDPA does not establish that FlashAttention executed.

Qwen long-run resource sample: about 2.94 GB process RSS, 3.81 GB driver GTT, 0.53 GB driver VRAM peak and 66.6 W mean APU PPT during the first run. These are overlapping counters. VibeVoice Large uses about 18.91 GB peak active PyTorch allocation; per-run allocator and driver readings are in the JSON receipts.

The supplied article is valuable for its cold/warm lesson. Its CustomVoice/Eric PyTorch 2.9.1/ROCm measurements are not a ceiling for Base Q8/Vulkan. Its timings alone do not prove kernel compilation caused the first-run effect, that resident GPU KV caches must cross PCIe, or that SDPA is one hardware feature. The F5 output is 27.2 seconds versus 197.5 seconds for Qwen despite the same-text claim; verify completed content before adopting the claimed equivalent-narration speedup. Detailed source-backed review is in `vibevoice-asr/article-review.md`. [Article](https://tinycomputers.io/posts/the-real-cost-of-running-qwen-tts-locally-three-machines-compared.html).

## Build and playback state

Pinned Qwen packages build on Nix; relay behavior and topology tests pass, and the complete flake evaluates. The on-demand coordinator service restores the saved voice, serializes synthesis, and idles out. The client uses SSH and its selected PipeWire sink. Stop/disconnect reaches the engine's cancellation callback. Weights are acquired into the NAS Library and explicitly loaned; runtime paths do not download weights or put them in the Nix store.

The proposed Qwen supervisor also checks host memory before starting and every 100 ms while running, terminating only its own engine below 16 GiB available host memory or at 64 GiB AMD device GTT. These device-wide emergency thresholds preserve headroom; they are a reactive guard, not a hard GPU allocation quota. Missing memory counters fail closed. Tests exercise pressure-triggered termination and healthy-process survival.

The user-visible `BO_VA (-12)` kernel errors came from the unrestricted C++ cloning experiment at 18:41–18:42 local time, alongside host allocation stalls and roughly 117 GiB of TTM allocations. This was a real desktop-impacting failure. The experimental VibeVoice TTS service is not present in the deployment configuration. The incident and recovery evidence are preserved under `benchmarks/coordinator-memory-incident/`. After adding the guard, four one-shot Qwen size tests and the complete chunked Zenbook request produced **zero new kernel messages**. The Zenbook received one 115.68-second WAV in 28.73 seconds including SSH and file finalization, with all 344 words independently verified; the relay logged 28.12 seconds and 68 ms first PCM after readiness. The user service then stopped cleanly with exit status zero. Twelve CPU behavior tests, the Nix package build and topology checks pass.

The worktree is reviewable but not merged or activated fleet-wide. Temporary test closures establish the working playback path. The existing dictation/ASR route remains operational while candidates are evaluated. Full wake-word, conversational orchestration and selection-to-speech integration are subsequent work, not implied by these runtime samples.

## Coverage and current architectural direction

The clear **TTS engineering leader on this coordinator** is Qwen3-TTS through qwentts.cpp: fast first delivery, complete chunked readings, working K-2SO conditioning and comparatively small measured memory use. Keep 1.7B Q8 as the baseline; the 0.6B and BF16 recordings remain available for listening before fixing size/precision. Voice resemblance is still a human preference judgment. The K-2SO reference is viable enough to continue, with three Qwen-designed male alternatives retained as fallbacks.

Ordinary VibeVoice ASR and streaming VibeVoice ASR remain separate architectural choices. The ordinary model supplies structured timestamps and passed the controlled technical text exactly. Streaming supplies incremental speaker-attributed text, subject to a roughly 3.47-second input-window floor before compute; 1.5B favored throughput and speaker separation on this fixture, while 7B favored technical wording. Neither ASR conclusion changes the TTS winner.

| Scope | Locally tested |
| --- | --- |
| Qwen runtimes | Serveurperso qwentts.cpp and Khimaros C++ on Vulkan |
| Qwen checkpoints | Base 1.7B Q8, Base 0.6B Q8, Base 1.7B BF16; VoiceDesign 1.7B Q8 for three generic seed voices |
| VibeVoice TTS | Recovered Large Python with eager and SDPA; current C++ Realtime 0.5B Q8 and cloning 1.5B Q8 |
| Ordinary VibeVoice ASR | Current C++ ASR 7B Q4_K with speaker labels and timestamps |
| Streaming VibeVoice ASR | September Python/ROCm 1.5B and larger 7B capacity control |
| Discussed, not locally benchmarked | Official Qwen Python, Rust Qwen variants, F5-TTS, CPU-only or other-machine performance |

Harness errors and bounded failures remain in the receipts. The recovered Large parser initially discarded unlabelled paragraphs; its default output-to-input limit then truncated a full-script attempt despite a larger nominal token budget. These are excluded from valid long results. The final harness labels every paragraph, asserts exact parsed input, raises the effective output limit, and independently detects reaching that limit. An initial whole-file CPU transcript also lost middle text, so long validation uses segmented checks where needed. These corrections prevent incomplete speech from being credited as faster narration.
