# Local model roster

The catalogue in [`../../lib/local-models.nix`](../../lib/local-models.nix)
is summarised here. It merges `lib/speech-intake-models.json`,
`lib/gufo-models.json`, `lib/ds4-models.json` and a few inline rows. Every byte
figure is the exact sum of the pinned file sizes (decimal GB), and every
revision is the pinned Hugging Face commit (abbreviated).

**A catalogue row is not a server.** Appearing here gives an artifact an
identity and a provenance record. Bytes move only when `library-fetch` fills
the NAS Library and an operator runs `local-models-borrow` on a host
([`README.md`](README.md) walks the transaction). Two engines serve rows:

- **Gufo** ([`../../modules/gufo.nix`](../../modules/gufo.nix)) on both Strix:
  `qwen38-flash-next-gguf` resident as `qwen3.8-flash-next` on
  `http://strix-coordinator:8731`; the Qwen3.8-27B alternate (`qwen3.8-27b`)
  after `gufo-switch qwen38-27b`; the TP2 fork with Flash-Next Q4 or Q8; the
  speech, ASR and image units on demand.
- **ds4** ([`../../modules/ds4.nix`](../../modules/ds4.nix)) on strix-worker:
  the DeepSeek V4.1 Flash 1017 Q2 as `deepseek-v4.1-flash` on
  `http://10.42.0.5:8732`, single host with SSD expert streaming, started by
  hand.

## Per-host wanted sets

Each Strix's `services.local-models.artifacts` is pinned by a `flake.nix`
assertion. It is everything the host holds: a default `local-models-borrow`
restores it and `local-models-prune` keeps it. The scoped manifests
(`/etc/gufo/tp2-q8-wanted.json`, `/etc/gufo/27b-q8-wanted.json`,
`/etc/ds4/wanted.json`) borrow one bundle alone; they do not change what a
host keeps.

| Host | Wanted artifacts | Served by |
|---|---|---|
| `strix-coordinator`, `strix-worker` | `qwen38-flash-next-gguf`, `qwen38-27b-gguf`, `qwen38-27b-q8-gguf`, `qwen38-27b-dflash2-gguf`, `qwen3-asr-1.7b`, `qwen3-tts-12hz-1.7b-base`, `qwen-image-2.1`, `vibevoice-asr-streaming-7b-bf16`, `qwen3-tts-1.7b-base-q8-0`, `qwen-k2so-midway-b`, `qwen3-tts-tokenizer-f32` | Gufo (Flash-Next at boot, the 27B or 27B Q8 after `gufo-switch`, ASR, TTS and image on demand); `call-diarize`; Qwen TTS on demand |
| `strix-worker` only | `deepseek-v41-flash-1017-q2-gguf` (via `services.ds4.wanted`), `qwen38-flash-next-q8-gguf` | ds4; `gufo-tp2` with Q8. The coordinator's disk cannot hold either (D-A) |
| `nas` | none; it holds the Library | — |

## The catalogue

| Artifact id | Kind | Precision | Source | Bytes | Serving |
|---|---|---|---|---|---|
| `qwen38-flash-next-gguf` | model (4 shards + MTP + BF16 projector) | UD-Q4_K_XL | `unsloth/Qwen3.8-Flash-Next-GGUF@38bb39e` | 115.03 GB | Gufo `gufo-llm`, the resident model |
| `qwen38-flash-next-q8-gguf` | model (6 shards + MTP + projector) | Q8_0 | `unsloth/Qwen3.8-Flash-Next-GGUF@38bb39e` | 191.92 GB | Gufo TP2 only |
| `qwen38-27b-gguf` | model + BF16 projector | UD-Q4_K_XL | `unsloth/Qwen3.8-27B-GGUF@4ca7207` | 18.49 GB | Gufo alternate `qwen38-27b` |
| `qwen38-27b-q8-gguf` | model + BF16 projector | UD-Q8_K_XL | `unsloth/Qwen3.8-27B-GGUF@4ca7207` | 32.39 GB | Gufo alternate `qwen38-27b-q8` |
| `qwen38-27b-dflash2-gguf` | draft | Q4_K_M | `z-lab/Qwen3.8-27B-DFlash2-GGUF@2d9571f` | 1.14 GB | the 27B's DFlash2 draft |
| `deepseek-v41-flash-1017-q2-gguf` | model | IQ2_XXS-Q2_K-imatrix | `kyuz0/deepseek-v4.1-flash-gguf@20408f6` | 365.71 GB | ds4, single host on strix-worker |
| `deepseek-v41-flash-vision-gguf` | mmproj (1017 vision) | BF16 | `kyuz0/deepseek-v4.1-flash-gguf@20408f6` | 0.97 GB | ds4 `--vision`; off until proven in the image |
| `deepseek-v41-flash-dspark-gguf` | draft (1017 DSpark) | MXFP4 | `kyuz0/deepseek-v4.1-flash-gguf@20408f6` | 7.97 GB | ds4 TP2 only (needs resident experts) |
| `qwen3-asr-1.7b` | model | — | `Qwen/Qwen3-ASR-1.7B@7278e1e` | 4.70 GB | Gufo `gufo-asr`, per job |
| `qwen3-tts-12hz-1.7b-base` | model | BF16 | `Qwen/Qwen3-TTS-12Hz-1.7B-Base@fd4b254` | 4.54 GB | Gufo `gufo-tts`, on demand |
| `qwen-image-2.1` | model (25-file snapshot) | — | `Qwen/Qwen-Image-2.1@b3179ad` | 33.13 GB | Gufo `gufo-image`, on demand |
| `minimax-h3-fl2va` | model (84 files) | BF16 | `MiniMaxAI/MiniMax-H3@42ed227` | 144.05 GB | licence accepted by Tom 2026-10-25; in the NAS Library; no strix wants it yet (100 GB free on strix-coordinator, 61 GB on strix-worker; Gufo video is upstream work in progress) |
| `qwen3-tts-1.7b-base-q8-0` | model | Q8_0 | `Serveurperso/Qwen3-TTS-GGUF@b7ee2e8` | 2.08 GB | `modules/qwen-tts.nix`, the one TTS model |
| `qwen3-tts-tokenizer-f32` | tokenizer | F32 | `Serveurperso/Qwen3-TTS-GGUF@b7ee2e8` | 0.65 GB | its codec |
| `qwen-k2so-midway-b` | template (voice) | — | local `speech/k2so-midway-b` | 0.003 GB | the one TTS voice |
| `vibevoice-asr-streaming-7b-bf16` | model (17-file snapshot) | BF16 | `microsoft/VibeVoice-ASR-Streaming-7B@60d858b` | 17.36 GB | `call-diarize`; the one diarization model |

Retired from the active catalogue and wanted sets: `deepseek-v4-flash-gguf`
and `deepseek-v4-flash-dspark-gguf` (2026-10-28, superseded by V4.1), every
`halogen-*` row (2026-10-23); the Library copies of all of these were deleted
on 2026-10-28 (`RETIRED-2026-10-28.tsv`), and on 2026-09-30 (sweep F1) `qwen3-embedding-8b-q8-0`
and the three Mage rows. Speech input (Voxtype, Parakeet, the wake listener)
left the fleet on 2026-09-30 (Tom; see `AGENTS.md`).

## The utility model

Callers name the stable ID `utility` and never a concrete model. The
`utility-model` wrapper forwards one chat-completions request to
`http://strix-coordinator:8731` as `qwen3.8-flash-next` and returns the
answer. `/drain` and `/print` are its callers; their flags are unchanged.

## Operating rules

- Two declared engines, Gufo and ds4, with one large model on a host's GPU at
  a time (`Conflicts=` between their text units). A different engine is a new
  module beside `modules/gufo.nix`, reviewed as such; it is never a row that
  quietly starts serving because it was borrowed.
- Runtime downloads (`-hf`, `hf download` from a service) are out. Bytes enter
  through `library-fetch` on the NAS and reach a host through
  `local-models-borrow`; `local-models-prune` is the only deleter.
- One TTS model (Qwen3-TTS with the K-2SO voice) and one diarization model
  (VibeVoice-ASR-Streaming-7B), per Tom's 2026-09-16 ruling in `DECISIONS.md`.
- There is no embedder row and no embeddings server.
