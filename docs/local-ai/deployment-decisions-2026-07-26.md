# Two-node local-AI deployment decisions

Status: final and active as of 2026-07-26.

This is the authoritative human-readable placement decision for the two Strix
Halo machines. The executable source of truth remains the allowlists in
`modules/strix.nix` and the immutable artifact metadata in
`lib/local-models.nix`.

## Coordinator

| Model | Payload | Backend / boundary | Download bytes |
|---|---|---|---:|
| `qwen3-vl-8b-ocr` | Q8_0 GGUF plus BF16 vision projector | ROCm through llama-swap | 9,872,089,504 |
| `qwen3-vl-32b-ocr` | Q4_K_M GGUF plus BF16 vision projector | ROCm through llama-swap | 20,962,485,696 |
| `qwen3-embedding-8b` | Q5_0 GGUF | ROCm through llama-swap | 5,291,991,360 |
| `qwen3.6-35b-a3b` | MXFP4 MoE GGUF | Vulkan through llama-swap | 21,706,144,736 |
| `qwopus3.6-27b-v2` | Q5_K_M GGUF | Vulkan through llama-swap | 19,231,097,088 |
| `gemma4-26b-a4b-qat` | QAT Q4_0 GGUF plus matched MTP head | Vulkan through llama-swap | 14,691,302,912 |
| `fara1.5-27b` | **Q8_0** GGUF plus BF16 vision projector | ROCm through llama-swap | 29,596,213,728 |
| `gemma4-it:e4b` | FastFlowLM Gemma4 E4B NPU2 snapshot | NPU peer through llama-swap | 9,087,470,597 |
| `gpt-oss:20b` | FastFlowLM GPT-OSS 20B NPU2 snapshot | NPU peer through llama-swap | 14,474,616,866 |
| Parakeet unified English 0.6B | Voxtype-managed ONNX/MIGraphX snapshot | Coordinator Voxtype user service | 2,515,028,028 |
| VibeVoice ASR | Full BF16 long-form ASR/diarization snapshot | Nix-rooted appliance payload; runtime service is future work | 17,348,322,081 |
| VibeVoice Large | Full BF16 multi-speaker TTS snapshot | Nix-rooted appliance payload; runtime service is future work | 18,686,995,855 |
| Qwen 2.5 7B tokenizer | Shared VibeVoice tokenizer payload | Nix-rooted appliance dependency | 11,487,545 |

Total model download payload: **183,475,245,996 bytes**, or **183.48 GB
(170.87 GiB)**. Nix derivation metadata, runtime caches, and MIGraphX compiler
caches are not included. The Nix-rooted subset is byte-exact; runtime-owned
FastFlowLM and Voxtype figures are the manifests observed on 2026-07-26 and can
change when their upstream model tags advance.

## Worker

| Model | Payload | Backend / boundary | Download bytes |
|---|---|---|---:|
| `qwen3.6-35b-a3b` | MXFP4 MoE GGUF | Vulkan through llama-swap | 21,706,144,736 |
| `qwopus3.6-27b-v2` | Q5_K_M GGUF | Vulkan through llama-swap | 19,231,097,088 |
| `gemma4-26b-a4b-qat` | QAT Q4_0 GGUF plus matched MTP head | Vulkan through llama-swap | 14,691,302,912 |
| `fara1.5-27b` | **Q8_0** GGUF plus BF16 vision projector | ROCm through llama-swap | 29,596,213,728 |
| `gemma4-it:e4b` | FastFlowLM Gemma4 E4B NPU2 snapshot | NPU peer through llama-swap | 9,087,470,597 |
| `gpt-oss:20b` | FastFlowLM GPT-OSS 20B NPU2 snapshot | NPU peer through llama-swap | 14,474,616,866 |

Total model download payload: **108,786,845,927 bytes**, or **108.79 GB
(101.32 GiB)**. Runtime caches are not included. The same runtime-tag caveat
applies to the two FastFlowLM rows.

## Decisions and exclusions

- NPU support is uniform. Both machines use translated IOMMU mode with
  `amd_iommu=on`; the worker no longer takes the former iGPU-only
  `amd_iommu=off` optimization. The worker must reboot when this generation is
  first activated so amdxdna can bind with the new kernel command line.
- FastFlowLM owns its two NPU2 snapshots as mutable runtime data under
  `~/.config/flm/models`. Each model has a loopback-only server and is exposed
  to callers only as a llama-swap peer.
- The GGUF and VibeVoice payloads are immutable, hash-checked Nix store paths.
  Only the explicit per-host allowlists root them. The catalog can retain more
  candidates without downloading them.
- Voxtype 0.7.5 offers several nominally 0.6B Parakeet variants. The largest
  variants are batch-only; `parakeet-unified-en-0.6b` is the only registry entry
  compatible with the enabled streaming pipeline. Voxtype downloads and
  verifies it idempotently before its coordinator service starts.
- VibeVoice ASR and TTS weights, configurations, indexes, and their shared Qwen
  tokenizer are downloaded now. Their dedicated ROCm service definitions are
  intentionally separate future work; they are not OpenAI-compatible LLMs and
  do not belong behind llama-swap.
- `qwen3-coder-next`, all uncensored models, and the retired DeepSeek V4/DS4
  payload remain cataloged only. None are downloaded by this deployment.
- Stable Diffusion remains outside the local-LLM route.
