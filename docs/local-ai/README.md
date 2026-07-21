# Local AI as appliances

The fleet provides a set of bounded appliances, not one undifferentiated LLM
daemon. Each appliance owns a workload, an inference implementation, immutable
model identity, resource class, and an explicit caller boundary.

## Safety state

`services.local-models.downloadAllModels` remains `false` on the Strix hosts.
The catalog is metadata only: evaluating it exposes names, revisions, file
sizes, LFS object IDs, and Nix SRI hashes, but does not fetch or root weights.
Tom manually lifts that gate in a later deployment pass. Monthly research and
roster edits are never allowed to lift it.

## Appliance map

| Appliance | Selected implementation | Serving boundary | State |
|---|---|---|---|
| Streaming speech-to-text | `asr-rs` dual Parakeet ONNX pipeline | Native dictation service; CPU-only | Existing source and model pins; Nix service reconciliation remains separate. |
| Document OCR/RAG | Qwen3-VL 8B primary, 32B refine, Qwen3 Embedding 8B | llama.cpp ROCm behind llama-swap | Selected and cataloged; weights gated off. |
| Code generation | Qwen3-Coder-Next + Qwopus + Gemma 4 opinion pool | llama.cpp Vulkan behind llama-swap | Selected and cataloged; weights gated off. |
| General text | FastFlowLM Gemma 4 E4B, Qwen 3.6 35B, DeepSeek V4 Flash | llama-swap only; DS4 is the fleet-wide escalation lane | Selected and cataloged; DS4 orchestration still needs its deployment pass. |
| Call transcription + diarization | Microsoft VibeVoice-ASR-HF | Dedicated PyTorch/ROCm batch service | Selected pre-deployment; not yet a Nix service. |
| Text-to-speech | VibeVoice Large community mirror | Dedicated PyTorch/ROCm batch service | Selected pre-deployment; mirror and runtime risk recorded. |
| Audio, image, and video generation | None | None | Parked. Stable Diffusion is explicitly outside the local-LLM route. |

## Text classes

- **Small and fast:** `gemma4-it:e4b` on the coordinator NPU. FastFlowLM owns
  these weights; llama-swap exposes it as a peer.
- **Daily general:** Qwen 3.6 35B-A3B MXFP4 on Vulkan.
- **SOTA escalation:** DeepSeek V4 Flash Q4 imatrix plus MTP through DS4 across
  both Strix Halo nodes.
- **Coder/swarm:** three separately addressable models. A caller may request
  pooled opinions, but the catalog does not hide them behind a synthetic model
  name or silently vote on results.
- **Uncensored:** three manually addressed, cross-family/refusal-removal routes.
  They are high-recall hypothesis generators, never arbiters, and must not enter
  automatic routing.

## Routing and scheduling boundaries

Every OpenAI-compatible local LLM or VLM call enters through llama-swap. Backend
ports are implementation details and are not caller APIs. Modality-specific
speech services get their own declared endpoints because they are not chat
completion servers.

Tally schedules, serializes, and proves the monthly community review described
in [`monthly-workflow.md`](monthly-workflow.md). It does not retrofit historical
pre-Nix notes into the current architecture.

## Sources of truth

1. [`../../lib/local-models.nix`](../../lib/local-models.nix) owns immutable
   artifact and deployment metadata.
2. [`../../modules/local-models.nix`](../../modules/local-models.nix) projects
   canonical rows into the Nix store and llama-swap only when the manual gate is
   true.
3. [`model-roster.md`](model-roster.md) is the human-readable view, including
   speech appliances that do not belong in the llama-swap catalog.
4. [`tallies/`](tallies/) records why the roster changed and the exact source
   pins reviewed each month.

The old documentation under [`../old/`](../old/) is evidence, not authority.
