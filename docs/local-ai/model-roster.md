# Local model roster

Anchor: 2026-07-26. “Canonical” marks an accepted catalog identity. Actual
download authority comes only from each host's explicit deployment and artifact
allowlists.

The Nix catalog contains 14 deployment rows, 20 artifacts, and 45 pinned files
totaling 431,543,209,001 bytes (401.91 GiB), including deferred and historical
entries. The active split is intentionally much narrower: see the
[final deployment decision](deployment-decisions-2026-07-26.md) for exact host
membership and totals. In particular, the coder-next, uncensored, and retired
DS4 weights are not materialized.

## llama-swap catalog

All llama.cpp rows use the dotfiles-pinned
[`ggml-org/llama.cpp@571d0d5`](https://github.com/ggml-org/llama.cpp/commit/571d0d540df04f25298d0e159e520d9fc62ed121).
The table links immutable Hugging Face revisions. A catalog row is not evidence
that its artifacts are selected on either host.

| Class | Public model ID | Exact artifact source | Inference | Evidence at anchor |
|---|---|---|---|---|
| Small / fast | `gemma4-it:e4b` | FastFlowLM runtime tag; no HF artifact is owned by this catalog | FastFlowLM NPU peer at `fd371409…`; callers enter through llama-swap | Active on both Strix NPUs |
| Small / fast | `gpt-oss:20b` | [`FastFlowLM/GPT-OSS-20B-NPU2@12ce92d`](https://huggingface.co/FastFlowLM/GPT-OSS-20B-NPU2/tree/12ce92d2bfa031761ab876b3b845a7dabeab1d98) via FastFlowLM runtime pull | FastFlowLM NPU peer; callers enter through llama-swap | Active on both Strix NPUs |
| General | `qwen3.6-35b-a3b` | [`unsloth/Qwen3.6-35B-A3B-GGUF@a483e9e`](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/tree/a483e9e6cbd595906af30beda3187c2663a1118c), `Qwen3.6-35B-A3B-MXFP4_MOE.gguf` | llama.cpp Vulkan | Exact benchmark bitstream: 82/84, nonce 3/3, 58.5 tok/s decode in `tesla_agent` |
| Coding pool 1 | `qwen3-coder-next` | [`unsloth/Qwen3-Coder-Next-GGUF@ce09c67`](https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF/tree/ce09c67b53bc8739eef83fe67b2f5d293c270632), `Qwen3-Coder-Next-UD-Q4_K_XL.gguf` | llama.cpp Vulkan | Exact benchmark bitstream: four-stage coding PASS, nonce 3/3, 44.4 tok/s decode |
| Coding pool 2 | `qwopus3.6-27b-v2` | [`Jackrong/Qwopus3.6-27B-v2-GGUF@ef90e98`](https://huggingface.co/Jackrong/Qwopus3.6-27B-v2-GGUF/tree/ef90e98f127675cd5457c71fb30ff184f751e963), `Qwopus3.6-27B-v2-Q5_K_M.gguf` | llama.cpp Vulkan | Exact Ciru profile: 42/148 BigCodeBench-Hard; kept distinct from stock Qwen 27B |
| Coding pool 3 | `gemma4-26b-a4b-qat` | [`google/gemma-4-26B-A4B-it-qat-q4_0-gguf@d1c082b`](https://huggingface.co/google/gemma-4-26B-A4B-it-qat-q4_0-gguf/tree/d1c082be9cf3c8a514acf63b8761f4b41935842e), `gemma-4-26B_q4_0-it.gguf`; MTP: [`unsloth/gemma-4-26B-A4B-it-qat-GGUF@7b92b5b`](https://huggingface.co/unsloth/gemma-4-26B-A4B-it-qat-GGUF/tree/7b92b5b28818151e8669af2e45e88d6086f490dd), `mtp-gemma-4-26B-A4B-it.gguf` | llama.cpp Vulkan, QAT-matched MTP | Current corrected-vocabulary bitstream is selected but unverified locally; prior benchmark used an older OID |
| Computer use | `fara1.5-27b` | [`bartowski/Fara1.5-27B-GGUF@dd7cba9`](https://huggingface.co/bartowski/Fara1.5-27B-GGUF/tree/dd7cba968d1a9c8feab0c2b85d93b117e6cc16fe), **Q8_0** plus BF16 projector | llama.cpp ROCm | Explicit Q8 choice; active on both hosts |
| Retired SOTA | `deepseek-v4-flash` | [`antirez/deepseek-v4-gguf@a88c423`](https://huggingface.co/antirez/deepseek-v4-gguf/tree/a88c423b511666d7ff7a4dcaee651669312bea97), full Q4 imatrix model + `DeepSeek-V4-Flash-MTP-Q4K-Q8_0-F32.gguf` | Historical [`ejpir/ds4-hip@3490c2e`](https://github.com/ejpir/ds4-hip/commit/3490c2e46c91331323dc0f2bfb7d3018e227fdff) dual-node run | Exact identity and roughly 11 tok/s witness retained; deployment retired on 2026-07-26, so its roughly 157 GiB weights are excluded from materialization |
| Uncensored / Heretic | `qwen3.6-35b-heretic` | [`Youssofal/Qwen3.6-35B-A3B-Abliterated-Heretic-GGUF@4c22107`](https://huggingface.co/Youssofal/Qwen3.6-35B-A3B-Abliterated-Heretic-GGUF/tree/4c22107061e656fb2a87a3ec2491bb61975eb581), Q4_K_M | llama.cpp Vulkan | Artifact provenance resolved; local behavior/quality run pending |
| Uncensored / tuned | `supergemma4-26b-uncensored` | [`Jiunsong/supergemma4-26b-uncensored-gguf-v2@3ea8c45`](https://huggingface.co/Jiunsong/supergemma4-26b-uncensored-gguf-v2/tree/3ea8c452a2b136875c0c8b529612bed39c81e27a), Q4_K_M | llama.cpp Vulkan | Exact Ciru throughput row: 66.07 tok/s decode |
| Uncensored / aggressive | `glm-4.7-flash-uncensored` | [`tripolskypetr/GLM-4.7-Flash-Uncensored-Aggressive-GGUF@5ad26dd`](https://huggingface.co/tripolskypetr/GLM-4.7-Flash-Uncensored-Aggressive-GGUF/tree/5ad26ddb3ea7d64bc56ba1dab20bc52e776439cd), Q4_K_M | llama.cpp Vulkan | Different family and refusal-removal route; local run pending |
| OCR primary | `qwen3-vl-8b-ocr` | [`unsloth/Qwen3-VL-8B-Instruct-GGUF@b93a7ee`](https://huggingface.co/unsloth/Qwen3-VL-8B-Instruct-GGUF/tree/b93a7ee713758252c555be4210c00540df954dc2), Q8_0 + `mmproj-BF16.gguf` | llama.cpp ROCm | Matched academic-rag result: judge 9.0/10, jaccard 0.870, about 52 s/page |
| OCR refine | `qwen3-vl-32b-ocr` | [`unsloth/Qwen3-VL-32B-Instruct-GGUF@b9262a3`](https://huggingface.co/unsloth/Qwen3-VL-32B-Instruct-GGUF/tree/b9262a359f54dead8e2609f6146e2fc3398fd0d9), Q4_K_M + `mmproj-BF16.gguf` | llama.cpp ROCm | Matched local table/math reconciliation winner |
| OCR embedding | `qwen3-embedding-8b` | [`Qwen/Qwen3-Embedding-8B-GGUF@69d0e58`](https://huggingface.co/Qwen/Qwen3-Embedding-8B-GGUF/tree/69d0e58a13e463cd99a9b83e3f5fee7c10265fab), Q5_0 | llama.cpp ROCm, embeddings + last pooling | Matched executable academic-rag config; resolves the stale Q8 label in older ledgers |

The machine-readable catalog additionally records exact byte sizes, upstream
LFS SHA-256/OIDs, SRI hashes, base/fine-tune revisions, host placement, runtime
arguments, benchmark IDs, and evidence classes in
[`../../lib/local-models.nix`](../../lib/local-models.nix).

## Speech appliances outside llama-swap

These identities do not enter llama-swap because their APIs and runtimes are
modality-specific. VibeVoice payloads are hash-pinned in the Nix store;
Voxtype owns its mutable model directory and verified bootstrap.

| Appliance | Model and source | Inference | State |
|---|---|---|---|
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
- DeepSeek V4's dual-node DS4 row is historical evidence, not a runnable roster
  member. The DS4 package remains installed, but its weights are not materialized.
- Audio, image, and video generation remain parked and have no roster entries.
