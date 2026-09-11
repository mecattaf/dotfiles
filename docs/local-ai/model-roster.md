# Local model roster

The catalogue in [`../../lib/local-models.nix`](../../lib/local-models.nix)
(Mage manifests factored into
[`../../lib/mage-models.nix`](../../lib/mage-models.nix)) has fifteen rows.
This page is read off that file; every byte figure is the exact sum of the
pinned file sizes (decimal GB), and every revision is the pinned Hugging Face
commit.

**A catalogue row is not a server.** Appearing here gives an artifact an
identity and a provenance record. Bytes move only when `library-fetch` fills
the NAS Library and an operator runs `local-models-borrow` on a host
([`README.md`](README.md) walks the transaction). Two rows have a declared
server, both on the worker and never resident together:
`halogen-qwen38-flash-next` (Halogen Flash, the everyday model, up at boot) and
`halogen-qwen38-27b` (halogen-server's Qwen3.8-27B, the alternate an operator
brings up with `halogen-switch qwen38-27b` and puts back with
`halogen-switch flash`).

## Per-host wanted sets

Each twin's `services.local-models.artifacts` is pinned by a `flake.nix`
assertion.

| Host | Wanted artifacts | Served by |
|---|---|---|
| `worker` | `halogen-qwen38-flash-next`, `halogen-qwen38-27b` | [`../../modules/halogen.nix`](../../modules/halogen.nix) at `http://worker:8731`; Flash resident at boot, the 27B only after `halogen-switch qwen38-27b` |
| `coordinator` | `qwen36-35b-a3b-mtp-ud-q8-k-xl`, `gemma4-12b-it-q8-0`, `gemma4-12b-it-mtp-q8-0`, `fara15-9b-q8-0`, `fara15-9b-mmproj-bf16` | an operator's hand-run `llama-server`; nothing declarative |
| `nas` | none; it holds the Library | — |

## The catalogue

| Artifact id | Kind | Precision | Source | Bytes | Serving |
|---|---|---|---|---|---|
| `halogen-qwen38-flash-next` | model (4-bit checkpoint + quality overlay + vision tower + flat tokenizer, 9 files) | W4B `.hgn` | [`peonist-ai/halogen-qwen3.8-flash-next@ac23b1b`](https://huggingface.co/peonist-ai/halogen-qwen3.8-flash-next/tree/ac23b1b223b4e9192d27c22367d4dbacf2b595ef) (base [`Qwen/Qwen3.8-Flash-Next`](https://huggingface.co/Qwen/Qwen3.8-Flash-Next)) | 127.47 GB | Halogen Flash server on the worker; the only thing that loads these bytes |
| `halogen-qwen38-27b` | model (dense checkpoint + flat tokenizer, 6 files) | P1W4D-D2 `.hgn` | [`peonist-ai/halogen-qwen3.8-27b@d92dc33`](https://huggingface.co/peonist-ai/halogen-qwen3.8-27b/tree/d92dc33afed1cdc073846c76e51090fa493ce74a) | 35.9 GB | `podman-halogen-qwen38-27b`, the alternate engine on `:8731`, text only |
| `qwen36-35b-a3b-mtp-ud-q8-k-xl` | model with integrated MTP | UD-Q8_K_XL | [`unsloth/Qwen3.6-35B-A3B-MTP-GGUF@5bc3e23`](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF/tree/5bc3e238d916f48a861bac2f8a1990a0e9b7e98d) | 39.10 GB | hand-run `llama-server` |
| `gemma4-12b-it-q8-0` | model | Q8_0 | [`unsloth/gemma-4-12b-it-GGUF@fc034cf`](https://huggingface.co/unsloth/gemma-4-12b-it-GGUF/tree/fc034cfff751157913579611efad8462ac1be606) | 12.67 GB | hand-run `llama-server` |
| `gemma4-12b-it-mtp-q8-0` | MTP head for the row above | Q8_0 | same repository and revision | 0.47 GB | passed to that `llama-server` |
| `fara15-9b-q8-0` | model (computer use) | Q8_0 | [`bartowski/Fara1.5-9B-GGUF@153cb27`](https://huggingface.co/bartowski/Fara1.5-9B-GGUF/tree/153cb27ac91d4a2b9391ecf278542e610d040178) | 9.55 GB | hand-run `llama-server`; `fara-cli` is the reference client |
| `fara15-9b-mmproj-bf16` | vision projector for the row above | BF16 | same repository and revision | 0.92 GB | passed as `--mmproj` |
| `qwen3-embedding-8b-q8-0` | model (text embeddings) | Q8_0 | [`Qwen/Qwen3-Embedding-8B-GGUF@69d0e58`](https://huggingface.co/Qwen/Qwen3-Embedding-8B-GGUF/tree/69d0e58a13e463cd99a9b83e3f5fee7c10265fab) | 8.05 GB | none; hand-run `llama-server --embedding` |
| `qwen3-vl-embedding-8b-q8-0` | model (multimodal embeddings) | Q8_0 | [`mradermacher/Qwen3-VL-Embedding-8B-GGUF@ffa4987`](https://huggingface.co/mradermacher/Qwen3-VL-Embedding-8B-GGUF/tree/ffa49879fdb91ed1a436fbc84f37b123f714bb13) | 8.05 GB | none; hand-run `llama-server --embedding` |
| `qwen3-vl-embedding-8b-mmproj-f16` | vision projector for the row above | F16 | same repository and revision | 1.16 GB | passed as `--mmproj` |
| `vibevoice-asr-bf16` | model (transcription + diarization, 10 files) | BF16 | [`microsoft/VibeVoice-ASR@d0c9efd`](https://huggingface.co/microsoft/VibeVoice-ASR/tree/d0c9efdb8d614685062c04425d91e01b6f37d944) | 17.35 GB | none; upstream PyTorch runtime |
| `vibevoice-large-bf16` | model (text-to-speech, 14 files) | BF16 | [`aoi-ot/VibeVoice-Large@1b81fec`](https://huggingface.co/aoi-ot/VibeVoice-Large/tree/1b81fecc784a076dcd935678db551871f4598ebf) — community mirror; provenance risk is explicit | 18.69 GB | none; upstream PyTorch runtime |
| `vibevoice-qwen25-7b-tokenizer` | tokenizer sidecar for both VibeVoice rows (4 files) | — | [`Qwen/Qwen2.5-7B@d149729`](https://huggingface.co/Qwen/Qwen2.5-7B/tree/d149729398750b98c0af14eb82c78cfe92750796) | 0.01 GB | — |
| `mage-flow-4b-turbo-bf16` | model (image generation, 43-file snapshot) | BF16 | [`mage-flow-community/Mage-Flow-Turbo@65bb350`](https://huggingface.co/mage-flow-community/Mage-Flow-Turbo/tree/65bb3500f0da9df6a41ec6383716fc02cf014773) | 17.51 GB | none; upstream `MageFlowPipeline`, see [`mage.md`](mage.md) |
| `mage-flow-edit-4b-turbo-bf16` | model (image editing, 43-file snapshot) | BF16 | [`mage-flow-community/Mage-Flow-Edit-Turbo@66df6fa`](https://huggingface.co/mage-flow-community/Mage-Flow-Edit-Turbo/tree/66df6fa1aba5b40cd4120739134292eab9779da3) | 17.51 GB | none; upstream `MageFlowPipeline`, see [`mage.md`](mage.md) |
| `mage-vl-bf16` | model (image/video understanding, 78-file snapshot) | BF16 | [`microsoft/Mage-VL@5c78cab`](https://huggingface.co/microsoft/Mage-VL/tree/5c78cab61938e73859b63724d9bf5cb88c477eaa) | 10.85 GB | none; offline Transformers |

## The utility model

Callers name the stable ID `utility` and never a concrete model. It resolves
to the worker's Halogen Flash server, and the `utility-model` wrapper on the
coordinator forwards one chat-completions request there and returns the
answer. `/drain` and `/print` are its callers; their flags are unchanged. The
server exposes no token counters, which is why the UTIL-01 sampler reports
`tokens_in` / `tokens_out` as `UNKNOWN` (`DEFERRED.md`, DF-U-D17-2).

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

- One declared server. A second engine is a second module beside
  `modules/halogen.nix`, reviewed as such; it is never a row that quietly
  starts serving because it was borrowed.
- Every loaned GGUF is Q8 (`Q8_0` or `UD-Q8_K_XL`). Projectors, MTP heads,
  speech and Mage snapshots, tokenizers and the halogen `.hgn` bundle are
  explicit format exceptions, not low-bit selections.
- Runtime downloads (`-hf`, `hf download` from a service) are forbidden by
  assertion. Bytes enter through `library-fetch` on the NAS and reach a host
  through `local-models-borrow`; `local-models-prune` is the only deleter.
- The text-only and multimodal embedders stay separate ids so a caller
  chooses benchmark strength or mixed-modal retrieval explicitly. Neither has
  a server until an operator starts one.
- Mage-Flow is a diffusion pipeline and Mage-VL an offline Transformers
  snapshot; neither is an OpenAI-compatible route.
- Audio and video generation remain parked. Mage-Flow owns the selected
  image-generation and image-editing lanes.
