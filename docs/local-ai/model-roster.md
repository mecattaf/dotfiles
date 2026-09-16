# Local model roster

The catalogue in [`../../lib/local-models.nix`](../../lib/local-models.nix)
(Mage manifests factored into
[`../../lib/mage-models.nix`](../../lib/mage-models.nix)) is summarised here
(the speech-intake JSON rows it also merges are listed in
`docs/speech-operations.md`). This page is read off that file; every byte figure is the exact sum of the
pinned file sizes (decimal GB), and every revision is the pinned Hugging Face
commit.

**A catalogue row is not a server.** Appearing here gives an artifact an
identity and a provenance record. Bytes move only when `library-fetch` fills
the NAS Library and an operator runs `local-models-borrow` on a host
([`README.md`](README.md) walks the transaction). Two rows have a declared
server, declared on both twins and never resident together on either:
`halogen-qwen38-flash-next` (Halogen Flash, the everyday model, up at boot on
the worker only) and `halogen-qwen38-27b` (halogen-server's Qwen3.8-27B, the
alternate an operator brings up with `halogen-switch qwen38-27b` and puts back
with `halogen-switch flash`). On the coordinator neither starts at boot;
`halogen-switch off` releases its GPU.

## Per-host wanted sets

Each twin's `services.local-models.artifacts` is pinned by a `flake.nix`
assertion.

| Host | Wanted artifacts | Served by |
|---|---|---|
| `worker` | `halogen-qwen38-flash-next`, `halogen-qwen38-27b` | [`../../modules/halogen.nix`](../../modules/halogen.nix) at `http://worker:8731`; Flash resident at boot, the 27B only after `halogen-switch qwen38-27b` |
| `coordinator` | `halogen-qwen38-flash-next`, `halogen-qwen38-27b`, `vibevoice-asr-streaming-7b-bf16`, plus the Qwen speech rows, Parakeet and wake words from `modules/qwen-tts.nix`, `home/speech.nix` and the host file | Halogen at `http://coordinator:8731` only after `halogen-switch`; streaming ASR per `call-diarize` run; Qwen TTS on demand |
| `nas` | none; it holds the Library | — |

## The catalogue

| Artifact id | Kind | Precision | Source | Bytes | Serving |
|---|---|---|---|---|---|
| `halogen-qwen38-flash-next` | model (4-bit checkpoint + quality overlay + vision tower + flat tokenizer, 9 files) | W4B `.hgn` | [`peonist-ai/halogen-qwen3.8-flash-next@ac23b1b`](https://huggingface.co/peonist-ai/halogen-qwen3.8-flash-next/tree/ac23b1b223b4e9192d27c22367d4dbacf2b595ef) (base [`Qwen/Qwen3.8-Flash-Next`](https://huggingface.co/Qwen/Qwen3.8-Flash-Next)) | 127.47 GB | Halogen Flash server (resident on the worker, operator-started on the coordinator); the only thing that loads these bytes |
| `halogen-qwen38-27b` | model (dense checkpoint + flat tokenizer, 6 files) | P1W4D-D2 `.hgn` | [`peonist-ai/halogen-qwen3.8-27b@d92dc33`](https://huggingface.co/peonist-ai/halogen-qwen3.8-27b/tree/d92dc33afed1cdc073846c76e51090fa493ce74a) | 35.9 GB | `podman-halogen-qwen38-27b`, the alternate engine on `:8731` of either twin, text only |
| `qwen3-embedding-8b-q8-0` | model (text embeddings) | Q8_0 | [`Qwen/Qwen3-Embedding-8B-GGUF@69d0e58`](https://huggingface.co/Qwen/Qwen3-Embedding-8B-GGUF/tree/69d0e58a13e463cd99a9b83e3f5fee7c10265fab) | 8.05 GB | none; hand-run `llama-server --embedding` |
| `vibevoice-asr-streaming-7b-bf16` | model (streaming transcription + speaker labels, 17-file snapshot with its own tokenizer) | BF16 | [`microsoft/VibeVoice-ASR-Streaming-7B@60d858b`](https://huggingface.co/microsoft/VibeVoice-ASR-Streaming-7B/tree/60d858b518b4e19d404af3737f848fc185b30177) | 17.36 GB | `call-diarize` on the coordinator; the one diarization model |
| `mage-flow-4b-turbo-bf16` | model (image generation, 43-file snapshot) | BF16 | [`mage-flow-community/Mage-Flow-Turbo@65bb350`](https://huggingface.co/mage-flow-community/Mage-Flow-Turbo/tree/65bb3500f0da9df6a41ec6383716fc02cf014773) | 17.51 GB | none; upstream `MageFlowPipeline`, see [`mage.md`](mage.md) |
| `mage-flow-edit-4b-turbo-bf16` | model (image editing, 43-file snapshot) | BF16 | [`mage-flow-community/Mage-Flow-Edit-Turbo@66df6fa`](https://huggingface.co/mage-flow-community/Mage-Flow-Edit-Turbo/tree/66df6fa1aba5b40cd4120739134292eab9779da3) | 17.51 GB | none; upstream `MageFlowPipeline`, see [`mage.md`](mage.md) |
| `mage-vl-bf16` | model (image/video understanding, 78-file snapshot) | BF16 | [`microsoft/Mage-VL@5c78cab`](https://huggingface.co/microsoft/Mage-VL/tree/5c78cab61938e73859b63724d9bf5cb88c477eaa) | 10.85 GB | none; offline Transformers |

## The utility model

Callers name the stable ID `utility` and never a concrete model. It resolves
to the worker's Halogen Flash server, and the `utility-model` wrapper on the
coordinator forwards one chat-completions request there and returns the
answer. `/drain` and `/print` are its callers; their flags are unchanged. The
server has no `/metrics`, but it logs one `serve_api:` line per request with its
prompt, cached and completion tokens; the UTIL-01 sampler on the worker reads
those lines per minute, so `tokens_in` / `tokens_out` are counted (dotfiles#312,
`DECISIONS.md` 2026-09-13).

## Voxtype and Parakeet

Live cursor dictation runs on the coordinator only, through
[`peteonrails/voxtype`](https://github.com/peteonrails/voxtype)'s
`onnx-migraphx` package, configured in `home/voxtype.nix`. The model is
`parakeet-unified-en-0.6b`. It is not a catalogue artifact: Voxtype owns and
verifies its own model directory under `~/.local/share/voxtype/models/`, and
the user service runs an idempotent `voxtype setup --download` before every
start. The pinned streaming window values (`0.32` / `5.6` / `0.32` seconds)
are load-bearing for parakeet-rs's mel-frame divisibility check, and
acceptance requires the journal to show the MIGraphX execution provider
initialising on gfx1151 with no CPU fallback.

## Operating rules

- One declared server family, Halogen, with one resident engine per host at a
  time. A different engine is a second module beside `modules/halogen.nix`,
  reviewed as such; it is never a row that quietly starts serving because it
  was borrowed.
- Every loaned GGUF is Q8 (`Q8_0` or `UD-Q8_K_XL`). Speech and Mage snapshots,
  tokenizers and the halogen `.hgn` bundles are explicit format exceptions, not
  low-bit selections.
- One TTS model (Qwen3-TTS with the K-2SO voice) and one diarization model
  (VibeVoice-ASR-Streaming-7B), per Tom's 2026-09-16 ruling in `DECISIONS.md`.
- Runtime downloads (`-hf`, `hf download` from a service) are forbidden by
  assertion. Bytes enter through `library-fetch` on the NAS and reach a host
  through `local-models-borrow`; `local-models-prune` is the only deleter.
- The text embedder has no server until an operator starts one. The
  multimodal Qwen3-VL embedder left with every Qwen3-VL row (Tom, 2026-09-16).
- Mage-Flow is a diffusion pipeline and Mage-VL an offline Transformers
  snapshot; neither is an OpenAI-compatible route.
- Audio and video generation remain parked. Mage-Flow owns the selected
  image-generation and image-editing lanes.
