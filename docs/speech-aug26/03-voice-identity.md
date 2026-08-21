# Voice identity: Jarvis and K-2SO

## Two useful target profiles

The local voice registry should eventually expose two distinct voices:

1. **Jarvis-style designed voice:** composed British machine intelligence, built through text-described voice design and tuned for comfortable long-form reading.
2. **K-2SO / Alan Tudyk clone:** a literal resemblance target conditioned from the cleanest recoverable K-2SO dialogue, optimized for the dry, blunt performance heard in *Rogue One*.

Both can use the same `/speak` and realtime TTS interfaces. They differ in how the voice source is constructed and evaluated.

## What `alexberardi/jarvis` actually contains

[`alexberardi/jarvis`](https://github.com/alexberardi/jarvis/tree/90ae07760f7c1e72061db4d0273047d9418d70f2) is a serious whole-assistant platform, not a reusable celebrity-voice model. The current TTS service uses:

- Piper `en_GB-alan-low`, a small 16 kHz generic British male voice; or
- Kokoro-82M, defaulting to the 24 kHz British male `bm_george` voice.

Neither is Paul Bettany/JARVIS cloning, reference-audio cloning, or text-described voice design. `jarvis-tts` exposes `/speak` and `/speak/stream`, not OpenAI `/v1/audio/speech`; voice/provider settings are global rather than per request. Its device settings cover CPU, CUDA, and MPS, while its container GPU path is NVIDIA-specific. It does not establish Strix Halo acceleration.

The project’s most reusable material lies elsewhere.

### Current summoning/audio path

One long-lived `AudioBus` owns the PyAudio capture stream, retains ring history, and fans 80 ms frames into named bounded/drop-oldest queues. ReSpeaker input arrives at 48 kHz and is resampled to OpenWakeWord’s 16 kHz frames. The default `hey_jarvis` model uses ONNX Runtime with threshold and debounce logic.

When accepted, the node:

1. pauses the ordinary wake consumer and ducks media;
2. snapshots about two seconds of wake audio for speaker matching;
3. plays a cached acknowledgement;
4. prewarms LLM/tool state while the command is still being spoken;
5. records until adaptive RMS silence;
6. sends command-only audio to Whisper and wake-plus-command audio to its speaker model;
7. consumes streamed PCM from the command center.

Closing the HTTP response cancels upstream generation and playback. Follow-up supports up to five turns with decreasing timeouts. Its “barge-in” is much narrower than full duplex: the user says `hey_jarvis` during TTS, playback stops, and the system returns to wake mode without retaining the replacement command. There is no acoustic echo cancellation.

Primary sources: [audio bus](https://github.com/alexberardi/jarvis-node-setup/blob/07aab710d9f233f19bf40e40e2f98bec1e8f833f/core/audio_bus.py), [listener](https://github.com/alexberardi/jarvis-node-setup/blob/07aab710d9f233f19bf40e40e2f98bec1e8f833f/scripts/voice_listener.py), and [wake loop](https://github.com/alexberardi/jarvis-node-setup/blob/07aab710d9f233f19bf40e40e2f98bec1e8f833f/core/wake_loop.py).

### Latency ideas worth borrowing

- Pre-rendered wake acknowledgement clips avoid waiting for live TTS; the author measured roughly 30 ms local playback in place of roughly 880 ms network synthesis.
- Short processing acknowledgements can mask a genuinely unavoidable wait.
- Model and tool warmup overlaps the user’s recording time.
- TTS streams sentence-by-sentence PCM with explicit format metadata.
- Capture and playback queues are bounded.
- Cancellation closes the upstream stream rather than merely muting stale audio.

Those patterns fit a small NixOS speech supervisor. The 13-service/~17-container platform, Pi installer, databases, observability, dynamic package system, global voice configuration, and Home Assistant control plane do not.

### Demo mismatch

At reviewed HEAD, the repository contains a commented TODO asking for a real 20–30 second wake-to-answer demo; no such demo is linked. The creator’s current [M4 Mac Mini installation video](https://www.youtube.com/watch?v=S7XTyQR6f30) is a silent installer/terminal recording. It demonstrates installation on Apple Metal, not wake detection, ASR/TTS quality, interruption, latency, or AMD behavior. The headline latency result is from an RTX 3080 Ti. Neither should be treated as Strix Halo evidence.

## What produces the K-2SO sound

Primary production interviews show Alan Tudyk trying multiple accents, choosing English/Imperial diction, and deliberately forming words as if he were a machine while performing K-2SO in motion capture. See [StarWars.com’s interview](https://www.starwars.com/news/andor-season-2-interview-alan-tudyk-k2so), [WIRED’s performance demonstration](https://www.wired.com/video/watch/how-alan-tudyk-became-rogue-one-s-k-2so), and [ILM’s production discussion](https://www.ilm.com/hal-hickel-discusses-rogue-one/).

No credible production source found in this review documents a signature heavy vocoder, pitch-shift, or formant-conversion chain. The recognizable result appears to be driven primarily by:

- precise British/Imperial diction;
- deliberate word formation and clipped consonants;
- low breathiness and even cadence;
- restrained emotional range;
- blunt literal delivery and dry humor;
- occasional childlike curiosity beneath machine confidence.

This is an inference from the production record, not proof that no light studio processing occurred. The theatrical signal is still edited, mixed, EQ’d, compressed, reverberated, and sometimes ADR’d.

## The available two-minute source is enough

The center channel of a surround mix is not an isolated dialogue stem. It may contain score, foley, other speakers, room response, scene reverb, dynamic EQ, compression, and effects. Separation can reduce those contaminants but can add warble, missing consonants, and phase artifacts of its own.

There are more than two minutes of genuinely clean K-2SO audio available locally. That changes the source-preparation problem substantially: the corpus is large enough to select multiple pristine references, cover varied phonemes and deliveries, and hold material back for honest evaluation.

It does **not** mean every engine should receive one two-minute concatenation. Zero-shot conditioners are usually optimized for short references and may truncate, average incompatible deliveries, or copy room tone when overfed. For these engines, a carefully chosen short excerpt can still outperform a long undifferentiated prompt. The full set is valuable because it provides a pool from which to select:

- acoustically dry close dialogue;
- no overlapping speaker;
- little or no score and machinery;
- stable loudness;
- complete phrases with accurate transcripts;
- complementary vowels, consonants, pitch, and pacing.

Do not simply concatenate every extracted line and send it to each engine. Build several purpose-specific references.

## Proposed source preparation pipeline

```text
local multichannel movie audio
  → preserve original channels and timestamps
  → subtitle/manual K-2SO line index
  → candidate center-channel segments
  → optional dialogue/source separation variants
  → trim overlaps, fades, loudness normalization
  → exact per-segment transcript
  → objective + listening quality scores
  → reference banks: 3 s / 8–10 s / 20–30 s / clean corpus
```

### 1. Build a timestamped line inventory

Start with subtitle timings or a local transcript, then correct every K-2SO boundary by ear. Retain scene, timestamp, spoken text, overlapping characters, score/foley level, reverberation, and delivery style. Automated speaker diarization can propose segments, but manual identity and transcript correction should be authoritative.

### 2. Generate several isolation candidates

For each useful line, compare:

- raw center channel;
- center-minus-correlated-left/right variants where appropriate;
- a dialogue/source-separation model output;
- a lightly denoised/de-reverberated version;
- the unprocessed segment as a control.

Do not aggressively clean by default. A little residual room sound is usually less damaging than metallic separation artifacts or erased high-frequency consonants. Archive every transformation and never overwrite the original segment.

### 3. Normalize conservatively

- Convert to mono only after channel comparison.
- Retain a high-quality lossless working rate; resample separately for each engine.
- Remove only leading/trailing material, with short fades that do not cut plosives or breaths.
- Avoid peak normalization per micro-clip, which creates inconsistent apparent distance.
- Use one corpus-level loudness target and reject clipped lines.
- Do not splice inside words or construct impossible cadence.

### 4. Transcribe exactly

Qwen’s strongest cloning path uses both `ref_audio` and the exact `ref_text`. Film subtitles often paraphrase or omit hesitations, so Parakeet/VibeVoice ASR can provide a draft but the final transcript must be manually aligned to the audible words. Preserve contractions, fillers, and meaningful punctuation that affect phrasing.

### 5. Rank reference quality

A small scoring manifest should combine:

- speech-to-background ratio;
- overlap probability;
- reverb/de-reverb severity;
- separation-artifact score;
- clipping and silence;
- transcript confidence;
- phoneme coverage;
- human listening grade;
- delivery match to the desired dry K-2SO persona.

The winning reference bank should include at least:

- **3-second pristine:** Qwen advertised minimum test;
- **8–10-second pristine:** shared zero-shot comparison across engines;
- **20–30-second diverse:** test whether longer context improves identity;
- **60- and 120-second variants:** duration-sweep inputs only for engines that actually accept long conditioning;
- **clean segmented corpus:** available for adaptation/fine-tuning experiments, not assumed necessary;
- **20–30-second held-out set:** never used for conditioning, reserved for blind identity and transcription tests.

## What each engine wants

| Engine | Reference mechanism | Best first K-2SO test |
|---|---|---|
| [Qwen3-TTS Base](https://github.com/QwenLM/Qwen3-TTS) | Three-second zero-shot is advertised; highest-fidelity path takes reference audio plus exact transcript; x-vector-only mode omits text at some quality cost | Compare 3 s, 6 s, 8–10 s, and 20–30 s with exact text; precompute the winning reusable clone prompt or C++ speaker/codec artifact |
| [Chatterbox](https://github.com/resemble-ai/chatterbox) | Official example uses an approximately 10-second reference and no transcript | Use the cleanest continuous 8–10 s phrase; test sensitivity to residual score/reverb |
| [MOSS-TTS](https://github.com/OpenMOSS/MOSS-TTS/blob/main/docs/moss_tts_model_card.md) | Short-reference zero-shot; simple mode needs no transcript; continuation mode has prefix-text rules | Start with the shared 8–10 s reference, then compare the 20–30 s bank if identity is weak |
| Kyuz0 VibeVoice Large path | Community Strix fork accepts custom WAV conditioning for the exact local VibeVoice Large artifact | Evaluate for long-form identity consistency after the shorter engines; record the exact fork behavior |
| Microsoft VibeVoice Realtime 0.5B | Current upstream realtime model uses precomputed voices and removed new acoustic enrollment | Not a K-2SO clone route; use only as a fixed-voice latency comparison |
| community VibeVoice 1.5B implementations | Some claim short raw-WAV cloning | Treat as a separate reproducibility test, not equivalent to the existing Large/Kyuz0 path |

## Fine-tuning is not the first move

Qwen, Chatterbox, and MOSS are designed to reveal voice-cloning quality from seconds of audio. Fine-tuning on all recovered lines adds several new failure modes:

- learning movie mix/reverb as part of the voice;
- overfitting a small set of phrases and emotions;
- degrading pronunciation outside the corpus;
- losing a clean baseline for comparing engines;
- much larger packaging and reproducibility burden.

First determine whether in-context conditioning is sufficient. Only consider adaptation if a clean reference produces the right accent/prosody but consistently misses timbre or long-form identity. If adaptation is tested, train from individually scored dry segments, keep the held-out 20–30 seconds untouched, and compare against the same zero-shot reference.

## Duration sweep for this corpus

Run `3 / 6 / 10 / 20 / 30 / 60 / 120` second variants only where the engine accepts them. Do not compare durations made from different acoustic material: construct a nested high-quality sequence wherever possible, then a separate diversity-optimized sequence. Score identity, pronunciation, cadence, copied ambience, and first-audio cost independently.

For the likely realtime winner, store its enrolled representation in the voice registry—Qwen reusable clone prompt, `.spk`/`.rvq`, embedding, or codec tokens—so `/speak` and conversation requests do not re-analyze two minutes of audio. Keep the full corpus for offline experimentation and re-enrollment, not per-request conditioning.

## Jarvis voice-design route

Jarvis is the complementary experiment because it needs no movie-source recovery. Qwen VoiceDesign or MOSS-VoiceGenerator can generate candidates from a direct brief:

> Composed low-mid British male machine intelligence; precise articulation; measured pace; restrained confidence; understated warmth and dry wit; smooth long-form narration; authoritative without theatrical exaggeration.

Generate several candidates, select by blind listening, render a clean phonetically varied seed, and enroll that seed into Qwen Base/Chatterbox/MOSS just as with K-2SO. This separates **voice generation** from **voice consistency**: the design model invents the timbre, while the cloning model makes it reusable.

## Post-processing experiment

Since no signature K-2SO vocoder chain was found, begin with the dry cloned output. Then compare only small reversible treatments:

- very gentle presence/low-mid EQ;
- light compression for even machine cadence;
- subtle saturation;
- an extremely low wet mix of short metallic doubling or comms coloration.

Keep processed and dry output separate. If the processed version wins only on short clips but becomes fatiguing over ten minutes, the voice registry should use different `assistant` and `narrator` playback profiles rather than baking the effect into the clone.

## Technical acceptance criteria

- recognizable K-2SO identity in blind A/B without revealing the engine;
- clean intelligibility on unseen technical prose;
- stable English accent and timbre for ten minutes;
- no learned score, reverb, or metallic separation residue during silence and fricatives;
- consistent loudness and pace across chunks;
- repeatable encoding from the archived reference bank;
- acceptable first-audio latency for conversation and a higher-fidelity mode for `/speak`;
- graceful pronunciation of paths, acronyms, French names, dates, and numbers.

The decisive comparison is not “all movie audio versus no movie audio.” It is which carefully prepared reference duration and cleanup variant gives each engine the strongest identity without importing the film mix.
