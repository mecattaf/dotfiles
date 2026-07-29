# Two-node local-AI deployment decisions

Status: final selection and authorized rollout as of 2026-07-26; FastFlowLM
lifecycle corrected on 2026-07-29.

This is the authoritative human-readable placement decision for the two Strix
Halo machines. The executable source of truth is the per-host llama-swap
allowlists and FastFlowLM roster in `modules/strix.nix`, plus the immutable
artifact and runtime metadata in `lib/local-models.nix`.

## Coordinator

| Model | Payload | Backend / boundary | Download bytes |
|---|---|---|---:|
| `qwen3-vl-8b-ocr` | Q8_0 GGUF plus BF16 vision projector | ROCm through llama-swap | 9,872,089,504 |
| `qwen3-vl-32b-ocr` | Q8_0 GGUF plus BF16 vision projector | ROCm through llama-swap | 36,018,055,616 |
| `qwen3-embedding-8b` | Q8_0 text embedder | ROCm through llama-swap | 8,047,105,824 |
| `qwen3-vl-embedding-8b` | Q8_0 multimodal embedder plus F16 vision projector | ROCm through llama-swap | 9,207,325,472 |
| `qwen3.6-35b-a3b` | UD-Q8_K_XL GGUF with integrated matched MTP block | Vulkan through llama-swap | 39,099,447,584 |
| `qwen3.6-27b` | Stock UD-Q8_K_XL GGUF with integrated matched MTP block | Vulkan through llama-swap | 35,776,484,480 |
| `gemma4-26b-a4b-it` | Q8_0 GGUF plus matched Q8_0 MTP head | Vulkan through llama-swap | 27,321,628,544 |
| `fara1.5-27b` | Q8_0 GGUF plus BF16 vision projector | ROCm through llama-swap | 29,596,213,728 |
| `gemma4-it:e4b` | FastFlowLM Gemma4 E4B NPU2 snapshot | Ad-hoc `flm run gemma4-it:e4b` | 9,087,470,597 |
| `gpt-oss:20b` | FastFlowLM GPT-OSS 20B NPU2 snapshot | Ad-hoc `flm run gpt-oss:20b` | 14,474,616,866 |
| Parakeet unified English 0.6B | Voxtype-managed ONNX/MIGraphX snapshot | Coordinator Voxtype user service | 2,515,028,028 |
| VibeVoice ASR | Full BF16 long-form ASR/diarization snapshot | Nix-rooted appliance payload; runtime service is future work | 17,348,322,081 |
| VibeVoice Large | Full BF16 multi-speaker TTS snapshot | Nix-rooted appliance payload; runtime service is future work | 18,686,995,855 |
| Qwen 2.5 7B tokenizer | Shared VibeVoice tokenizer payload | Nix-rooted appliance dependency | 11,487,545 |

Total model download payload: **257,062,271,724 bytes**, or **257.06 GB
(239.41 GiB)**. Nix derivation metadata, runtime caches, and MIGraphX compiler
caches are not included. The Nix-rooted subset is byte-exact; runtime-owned
FastFlowLM and Voxtype figures are the manifests observed on 2026-07-26 and can
change when their upstream model tags advance.

The text-only and VL embedders are complementary. Qwen3-Embedding-8B remains
the stronger supplied text benchmark choice; Qwen3-VL-Embedding-8B adds
text/image/screenshot/video and mixed-modal retrieval. The VL route is locally
matched: text and image smoke requests through llama-swap each returned one
normalized 4,096-dimensional embedding on the coordinator.

## Worker

| Model | Payload | Backend / boundary | Download bytes |
|---|---|---|---:|
| `qwen3.6-35b-a3b` | UD-Q8_K_XL GGUF with integrated matched MTP block | Vulkan through llama-swap | 39,099,447,584 |
| `qwen3.6-27b` | Stock UD-Q8_K_XL GGUF with integrated matched MTP block | Vulkan through llama-swap | 35,776,484,480 |
| `gemma4-26b-a4b-it` | Q8_0 GGUF plus matched Q8_0 MTP head | Vulkan through llama-swap | 27,321,628,544 |
| `fara1.5-27b` | Q8_0 GGUF plus BF16 vision projector | ROCm through llama-swap | 29,596,213,728 |
| `gemma4-it:e4b` | FastFlowLM Gemma4 E4B NPU2 snapshot | Ad-hoc `flm run gemma4-it:e4b` | 9,087,470,597 |
| `gpt-oss:20b` | FastFlowLM GPT-OSS 20B NPU2 snapshot | Ad-hoc `flm run gpt-oss:20b` | 14,474,616,866 |

Total model download payload: **155,355,861,799 bytes**, or **155.36 GB
(144.69 GiB)**. Runtime caches are not included. The same runtime-tag caveat
applies to the two FastFlowLM rows. Qwen 3.6 27B is fetched and hash-verified
once in the coordinator's Nix store, then its immutable NAR is copied to the
worker over the directly connected Thunderbolt interface; the worker does not
download a second copy from Hugging Face.

## Precision policy and special cases

- Every active llama.cpp model and external MTP weight is Q8: `Q8_0` or the
  higher-fidelity `UD-Q8_K_XL` tier. The active catalog has a flake assertion
  enforcing that invariant.
- Vision projectors are separate encoder/merger sidecars, not the LLM quant
  tier. They remain F16/BF16 for fidelity. VibeVoice speech snapshots likewise
  retain their upstream BF16 format.
- FastFlowLM owns its NPU2 snapshots as native runtime data under
  `~/.config/flm/models`. In particular, GPT-OSS is an upstream Q4_1 NPU2
  package; it is an explicit runtime-format exception, not a low-bit GGUF
  selection. Neither model has a NixOS serve unit or llama-swap peer. The
  ordinary `flm run <model>` CLI is the activation boundary: it loads one model
  for the interactive command and releases it on exit. Existing runtime files
  remain local; a missing model is fetched explicitly with `flm pull <model>`.
- Voxtype owns and verifies its Parakeet snapshot as mutable user data. Voxtype
  0.7.5 lists larger nominally 0.6B variants, but those are batch-only;
  `parakeet-unified-en-0.6b` is the largest registry entry compatible with the
  enabled streaming path. Its coordinator service performs an idempotent
  download before startup.

## Hardware and operational decisions

- NPU support is uniform. Both machines use translated IOMMU mode with
  `amd_iommu=on`; the worker no longer takes the former iGPU-only
  `amd_iommu=off` optimization. The worker must reboot when this generation is
  first activated so amdxdna can bind with the new kernel command line.
- Managed local LLM and VLM calls enter through llama-swap. A deterministic
  `<__media__>` marker is inherited by llama.cpp children so multimodal
  embedding clients can address transient backends consistently.
- llama-swap's systemd-managed cache directory is exported as `XDG_CACHE_HOME`.
  Mesa/RADV shader caches therefore persist across on-demand model swaps without
  granting the dynamic service user a general writable home directory.
- Ad-hoc NPU inference uses FastFlowLM's CLI directly and never starts at boot.
- GGUF and VibeVoice payloads are immutable, hash-checked Nix store paths. Only
  explicit per-host selections root them; catalog-only candidates do not
  download.
- VibeVoice ASR and TTS weights, configurations, indexes, and shared tokenizer
  are downloaded now. Their dedicated ROCm services remain separate future
  work because they are not OpenAI-compatible LLMs and do not belong behind
  llama-swap.
- Qwen3-Coder-Next, all uncensored models, and the retired DeepSeek V4/DS4
  payload remain catalog-only. None are downloaded by this deployment.
- Stable Diffusion remains outside the local-LLM route.
