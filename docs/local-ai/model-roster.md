# Local model roster

Anchor: 2026-07-29. “Canonical” marks an accepted catalog identity. Actual
download authority comes only from the coordinator's explicit deployment and
artifact allowlists.

The Nix catalog contains 15 deployment rows, 23 artifacts, and 209 pinned files
totaling 382,552,147,731 logical bytes (356.28 GiB), including deferred and
catalog-only entries. The active set is intentionally much narrower: see the
[current deployment decision](deployment-decisions-2026-07-29.md) for exact
coordinator membership and totals. Mage's two highly overlapping Flow
snapshots account for logical bytes per complete repository; Nix reuses their
identical fixed-output files, as detailed in [`mage.md`](mage.md). In particular,
the coder-next and uncensored weights are not materialized, and the retired DS4
artifacts are absent entirely.

## Model and appliance catalog

All llama.cpp rows use the dotfiles-pinned
[`ggml-org/llama.cpp@571d0d5`](https://github.com/ggml-org/llama.cpp/commit/571d0d540df04f25298d0e159e520d9fc62ed121).
The table links immutable Hugging Face revisions. A catalog row is not evidence
that its artifacts are selected by the coordinator. The FastFlowLM rows are direct
runtime appliances, not llama-swap deployments.

| Class | Public model ID | Exact artifact source | Inference | Evidence at anchor |
|---|---|---|---|---|
| Small / fast | `gemma4-it:e4b` | FastFlowLM runtime tag; no HF artifact is owned by this catalog | Ad-hoc `flm run gemma4-it:e4b` | Available on the coordinator NPU with zero boot residency |
| Small / fast | `gpt-oss:20b` | [`FastFlowLM/GPT-OSS-20B-NPU2@12ce92d`](https://huggingface.co/FastFlowLM/GPT-OSS-20B-NPU2/tree/12ce92d2bfa031761ab876b3b845a7dabeab1d98) via FastFlowLM runtime pull | Ad-hoc `flm run gpt-oss:20b` | Available on the coordinator NPU with zero boot residency |
| General | `qwen3.6-35b-a3b` | [`unsloth/Qwen3.6-35B-A3B-MTP-GGUF@5bc3e23`](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF/tree/5bc3e238d916f48a861bac2f8a1990a0e9b7e98d), `Qwen3.6-35B-A3B-UD-Q8_K_XL.gguf` | llama.cpp Vulkan with integrated matched MTP | Exact Strix Halo benchmark: 46.33 tok/s decode and 1045 tok/s 512-token prefill |
| Coding | `qwen3.6-27b` | stock [`Qwen/Qwen3.6-27B@6a9e13b`](https://huggingface.co/Qwen/Qwen3.6-27B/tree/6a9e13bd6fc8f0983b9b99948120bc37f49c13e9), quantized by [`unsloth/Qwen3.6-27B-MTP-GGUF@5cb35eb`](https://huggingface.co/unsloth/Qwen3.6-27B-MTP-GGUF/tree/5cb35eb3dcbf52dbce5f87dbc64df6aaffadcace) as `Qwen3.6-27B-UD-Q8_K_XL.gguf` | llama.cpp Vulkan with integrated matched MTP | Pi chat locally matched on coordinator with active MTP draft acceptance and RADV render-node use; stock checkpoint, not a fine-tune |
| Coding candidate | `qwen3-coder-next` | [`unsloth/Qwen3-Coder-Next-GGUF@ce09c67`](https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF/tree/ce09c67b53bc8739eef83fe67b2f5d293c270632), `Qwen3-Coder-Next-UD-Q4_K_XL.gguf` | llama.cpp Vulkan | Catalog-only historical candidate; its low-bit artifact is excluded from the active coordinator allowlist by the Q8 policy |
| Coding | `gemma4-26b-a4b-it` | [`unsloth/gemma-4-26B-A4B-it-GGUF@c099eb4`](https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/tree/c099eb48e663fd284577b04978a94ffccb261841), `gemma-4-26B-A4B-it-Q8_0.gguf` plus `MTP/mtp-gemma-4-26B-A4B-it-Q8_0.gguf` | llama.cpp Vulkan with matched Q8 MTP | Active non-QAT instruction checkpoint; Google's QAT identity was dropped because that release is Q4_0-only |
| Computer use | `fara1.5-27b` | [`bartowski/Fara1.5-27B-GGUF@dd7cba9`](https://huggingface.co/bartowski/Fara1.5-27B-GGUF/tree/dd7cba968d1a9c8feab0c2b85d93b117e6cc16fe), **Q8_0** plus BF16 projector | llama.cpp ROCm | Explicit Q8 choice; active on coordinator |
| Uncensored / Heretic | `qwen3.6-35b-heretic` | [`Youssofal/Qwen3.6-35B-A3B-Abliterated-Heretic-GGUF@4c22107`](https://huggingface.co/Youssofal/Qwen3.6-35B-A3B-Abliterated-Heretic-GGUF/tree/4c22107061e656fb2a87a3ec2491bb61975eb581), Q4_K_M | llama.cpp Vulkan | Artifact provenance resolved; local behavior/quality run pending |
| Uncensored / tuned | `supergemma4-26b-uncensored` | [`Jiunsong/supergemma4-26b-uncensored-gguf-v2@3ea8c45`](https://huggingface.co/Jiunsong/supergemma4-26b-uncensored-gguf-v2/tree/3ea8c452a2b136875c0c8b529612bed39c81e27a), Q4_K_M | llama.cpp Vulkan | Exact Ciru throughput row: 66.07 tok/s decode |
| Uncensored / aggressive | `glm-4.7-flash-uncensored` | [`tripolskypetr/GLM-4.7-Flash-Uncensored-Aggressive-GGUF@5ad26dd`](https://huggingface.co/tripolskypetr/GLM-4.7-Flash-Uncensored-Aggressive-GGUF/tree/5ad26ddb3ea7d64bc56ba1dab20bc52e776439cd), Q4_K_M | llama.cpp Vulkan | Different family and refusal-removal route; local run pending |
| OCR primary | `qwen3-vl-8b-ocr` | [`unsloth/Qwen3-VL-8B-Instruct-GGUF@b93a7ee`](https://huggingface.co/unsloth/Qwen3-VL-8B-Instruct-GGUF/tree/b93a7ee713758252c555be4210c00540df954dc2), Q8_0 + `mmproj-BF16.gguf` | llama.cpp ROCm | Matched academic-rag result: judge 9.0/10, jaccard 0.870, about 52 s/page |
| OCR refine | `qwen3-vl-32b-ocr` | [`unsloth/Qwen3-VL-32B-Instruct-GGUF@b9262a3`](https://huggingface.co/unsloth/Qwen3-VL-32B-Instruct-GGUF/tree/b9262a359f54dead8e2609f6146e2fc3398fd0d9), Q8_0 + `mmproj-BF16.gguf` | llama.cpp ROCm | High-fidelity replacement for the matched local table/math reconciliation winner |
| Text embedding | `qwen3-embedding-8b` | [`Qwen/Qwen3-Embedding-8B-GGUF@69d0e58`](https://huggingface.co/Qwen/Qwen3-Embedding-8B-GGUF/tree/69d0e58a13e463cd99a9b83e3f5fee7c10265fab), Q8_0 | llama.cpp ROCm, embeddings + last pooling | Stronger supplied text-only benchmark choice; active on coordinator |
| Multimodal embedding | `qwen3-vl-embedding-8b` | [`mradermacher/Qwen3-VL-Embedding-8B-GGUF@ffa4987`](https://huggingface.co/mradermacher/Qwen3-VL-Embedding-8B-GGUF/tree/ffa49879fdb91ed1a436fbc84f37b123f714bb13), Q8_0 + F16 projector | llama.cpp ROCm, embeddings + last pooling + L2 normalization | Adds text/image/screenshot/video retrieval; coordinator-only, locally matched with text and image requests through llama-swap |

The machine-readable catalog additionally records exact byte sizes, upstream
LFS SHA-256/OIDs, SRI hashes, base/fine-tune revisions, host placement, runtime
arguments, benchmark IDs, and evidence classes in
[`../../lib/local-models.nix`](../../lib/local-models.nix).

## Other appliances and snapshots outside the current llama-swap roster

These identities are not current llama-swap rows because their APIs and
runtimes are modality-specific or not yet proven on gfx1151. Mage-Flow is a
direct diffusion pipeline. Mage-VL's future online boundary is upstream's
custom OpenAI-compatible SGLang branch; only that server, once packaged and
verified on ROCm, belongs behind llama-swap. Mage and VibeVoice payloads are
hash-pinned in the Nix store; Voxtype owns its mutable model directory and
verified bootstrap.

| Appliance | Model and source | Inference | State |
|---|---|---|---|
| Text-to-image | Mage-Flow 4B [`Turbo`](https://huggingface.co/mage-flow-community/Mage-Flow-Turbo) community duplicate | Upstream `MageFlowPipeline` / `mage-flow` / Gradio | Four-step BF16 snapshot is Nix-rooted; Base and RL are intentionally absent |
| Instruction image editing | Mage-Flow-Edit 4B [`Turbo`](https://huggingface.co/mage-flow-community/Mage-Flow-Edit-Turbo) community duplicate | Upstream `MageFlowPipeline.edit` / `mage-flow-edit` / Gradio | Four-step BF16 snapshot is Nix-rooted; same runtime gate as generation |
| Image/video understanding + proactive streaming | [`microsoft/Mage-VL@5c78cab`](https://huggingface.co/microsoft/Mage-VL/tree/5c78cab61938e73859b63724d9bf5cb88c477eaa) | Offline Transformers; online custom `feat/mage-vl` SGLang | Complete BF16 checkpoint, gate, codec code, and DCVC weights are Nix-rooted; runtime service pending ROCm proof |
| Live cursor dictation | [`parakeet-unified-en-0.6b`](https://huggingface.co/bobNight/parakeet-unified-en-0.6b-onnx), the streaming-compatible TDT v3 family model selected by the pinned Voxtype registry | [`peteonrails/voxtype@f972766`](https://github.com/peteonrails/voxtype/commit/f97276661d9b723aa3236f03879650a2a06c3ec3), canonical `onnx-migraphx` package | Coordinator service downloads and verifies it automatically before start |
| Call transcription + diarization | [`microsoft/VibeVoice-ASR@d0c9efd`](https://huggingface.co/microsoft/VibeVoice-ASR/tree/d0c9efdb8d614685062c04425d91e01b6f37d944) | PyTorch/Transformers on ROCm | Full BF16 payload and pinned Qwen tokenizer are rooted on coordinator; service pending |
| Text-to-speech | [`aoi-ot/VibeVoice-Large@1b81fec`](https://huggingface.co/aoi-ot/VibeVoice-Large/tree/1b81fecc784a076dcd935678db551871f4598ebf) | [`kyuz0/amd-strix-halo-voice-toolbox@ab13312`](https://github.com/kyuz0/amd-strix-halo-voice-toolbox/commit/ab13312787f8c81d9527495abafeefed91051df2), PyTorch ROCm | Full BF16 payload and pinned Qwen tokenizer are rooted on coordinator; service pending; mirror provenance risk remains explicit |

### Voxtype bootstrap and live gate

Home Manager owns the Voxtype package, generated config, and one user service.
Weights remain mutable user data. The coordinator user service runs the
equivalent of the following idempotent bootstrap before every start:

```console
voxtype setup --download --model parakeet-unified-en-0.6b --quiet
```

The pinned Voxtype setup path verifies each downloaded file against the
Voxtype model manifest and writes the model beneath
`~/.local/share/voxtype/models/parakeet-unified-en-0.6b/`; neither the weights
nor generated artifacts belong in Git or the Nix store. Current upstream
explicitly rejects `parakeet-tdt-0.6b-v3` with `streaming = true`: that
similarly named model is batch-only, while the selected unified model is the
supported cache-aware TDT v3 streaming path.

The first MIGraphX graph compile may be slow. Later starts should reuse
`$XDG_CACHE_HOME/voxtype/migraphx` (normally
`~/.cache/voxtype/migraphx`). Acceptance requires the journal to show the
MIGraphX execution provider initializing on gfx1151 without a CPU fallback;
`voxtype status --extended --format json` identifies the configured ONNX
MIGraphX variant but does not replace that journal check.

## Operating rules

- Uncensored rows are catalog-only until a later explicit placement decision.
- The active coder models expose individual IDs. Ensemble policy belongs in the
  caller and must preserve each response and attribution; Qwen3-Coder-Next is
  catalog-only.
- The 8B OCR model drains by default. The 32B model is conditional refinement,
  not a permanently co-resident second server.
- The text-only and multimodal embedders remain separate model IDs so callers
  can choose benchmark strength or mixed-modal retrieval explicitly.
- FastFlowLM models are ad-hoc CLI workloads. Do not configure `flm serve`
  units or add their model IDs as llama-swap peers.
- Mage-Flow snapshots are direct diffusion workloads and never llama-swap
  rows. Mage-VL gets a row only with the upstream-compatible custom SGLang
  backend, never by relabeling it as llama.cpp or stock vLLM.
- The former DeepSeek V4/DS4 topology is not an active catalog row. Its useful
  benchmark and runbook evidence remains in `docs/old/`.
- Audio and video generation remain parked. Mage-Flow now owns the selected
  image-generation and image-editing lanes.
