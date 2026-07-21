# Local model roster

Anchor: 2026-07-22. “Canonical” means selected roster identity, not permission
to fetch or run it. The manual `downloadAllModels = false` gate remains the
deployment authority.

The Nix catalog contains 12 deployment rows and 15 pinned files totaling
365,900,189,792 bytes (340.77 GiB). If the global gate were lifted without a
placement change, the current projection would root 273,678,128,448 bytes on
the coordinator and 365,900,189,792 bytes on the exhaustive worker. Those
figures exclude FastFlowLM-owned NPU weights and the speech appliances. This is
one reason the gate must remain closed until the deployment pass.

## llama-swap catalog

All llama.cpp rows use the dotfiles-pinned
[`ggml-org/llama.cpp@571d0d5`](https://github.com/ggml-org/llama.cpp/commit/571d0d540df04f25298d0e159e520d9fc62ed121).
The table links immutable Hugging Face revisions; no artifact was downloaded to
produce it.

| Class | Public model ID | Exact artifact source | Inference | Evidence at anchor |
|---|---|---|---|---|
| Small / fast | `gemma4-it:e4b` | FastFlowLM runtime tag; no HF artifact is owned by this catalog | FastFlowLM NPU peer at `fd371409…`; callers enter through llama-swap | Matched locally; already the bootstrap utility lane |
| General | `qwen3.6-35b-a3b` | [`unsloth/Qwen3.6-35B-A3B-GGUF@a483e9e`](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/tree/a483e9e6cbd595906af30beda3187c2663a1118c), `Qwen3.6-35B-A3B-MXFP4_MOE.gguf` | llama.cpp Vulkan | Exact benchmark bitstream: 82/84, nonce 3/3, 58.5 tok/s decode in `tesla_agent` |
| Coding pool 1 | `qwen3-coder-next` | [`unsloth/Qwen3-Coder-Next-GGUF@ce09c67`](https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF/tree/ce09c67b53bc8739eef83fe67b2f5d293c270632), `Qwen3-Coder-Next-UD-Q4_K_XL.gguf` | llama.cpp Vulkan | Exact benchmark bitstream: four-stage coding PASS, nonce 3/3, 44.4 tok/s decode |
| Coding pool 2 | `qwopus3.6-27b-v2` | [`Jackrong/Qwopus3.6-27B-v2-GGUF@ef90e98`](https://huggingface.co/Jackrong/Qwopus3.6-27B-v2-GGUF/tree/ef90e98f127675cd5457c71fb30ff184f751e963), `Qwopus3.6-27B-v2-Q5_K_M.gguf` | llama.cpp Vulkan | Exact Ciru profile: 42/148 BigCodeBench-Hard; kept distinct from stock Qwen 27B |
| Coding pool 3 | `gemma4-26b-a4b-qat` | [`google/gemma-4-26B-A4B-it-qat-q4_0-gguf@d1c082b`](https://huggingface.co/google/gemma-4-26B-A4B-it-qat-q4_0-gguf/tree/d1c082be9cf3c8a514acf63b8761f4b41935842e), `gemma-4-26B_q4_0-it.gguf`; MTP: [`unsloth/gemma-4-26B-A4B-it-qat-GGUF@7b92b5b`](https://huggingface.co/unsloth/gemma-4-26B-A4B-it-qat-GGUF/tree/7b92b5b28818151e8669af2e45e88d6086f490dd), `mtp-gemma-4-26B-A4B-it.gguf` | llama.cpp Vulkan, QAT-matched MTP | Current corrected-vocabulary bitstream is selected but unverified locally; prior benchmark used an older OID |
| SOTA | `deepseek-v4-flash` | [`antirez/deepseek-v4-gguf@a88c423`](https://huggingface.co/antirez/deepseek-v4-gguf/tree/a88c423b511666d7ff7a4dcaee651669312bea97), full Q4 imatrix model + `DeepSeek-V4-Flash-MTP-Q4K-Q8_0-F32.gguf` | [`ejpir/ds4-hip@3490c2e`](https://github.com/ejpir/ds4-hip/commit/3490c2e46c91331323dc0f2bfb7d3018e227fdff), dual node | Exact weight identity matched locally at about 11 tok/s; Nix coordinator/worker launch orchestration is not implemented yet |
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

These are selected pre-deployment identities. They do not enter the GGUF store
or llama-swap because their APIs and runtimes are modality-specific. Their Nix
services must be implemented and validated separately before any weight fetch.

| Appliance | Model and immutable source | Inference | State |
|---|---|---|---|
| Streaming preview / end-of-utterance | `realtime_eou_120m-v1-onnx` in [`altunenes/parakeet-rs@a61d281`](https://huggingface.co/altunenes/parakeet-rs/tree/a61d2818df4659c956b9661a9447f46e98c15126) | [`mecattaf/asr-rs@38c638a`](https://github.com/mecattaf/asr-rs/commit/38c638a6f50947a053e6799b4465cad793d91534), ONNX Runtime on CPU | Selected existing streaming lane |
| Final dictation | [`istupakov/parakeet-tdt-0.6b-v2-onnx@0bbb45a`](https://huggingface.co/istupakov/parakeet-tdt-0.6b-v2-onnx/tree/0bbb45a3365852604aef28b538a8f066f4ccaa85) | Same `asr-rs` process; ONNX Runtime on CPU | Selected existing finalize lane |
| Call transcription + diarization | [`microsoft/VibeVoice-ASR-HF@f22241c`](https://huggingface.co/microsoft/VibeVoice-ASR-HF/tree/f22241c2062b3b25272bf117397e03d73381037a) | [`microsoft/VibeVoice@303b283`](https://github.com/microsoft/VibeVoice/commit/303b2833e01cff4578ec278bbfe536da54bd19fe), PyTorch/Transformers on ROCm | Selected, service and matched Strix run pending |
| Text-to-speech | [`aoi-ot/VibeVoice-Large@1b81fec`](https://huggingface.co/aoi-ot/VibeVoice-Large/tree/1b81fecc784a076dcd935678db551871f4598ebf) | [`kyuz0/amd-strix-halo-voice-toolbox@ab13312`](https://github.com/kyuz0/amd-strix-halo-voice-toolbox/commit/ab13312787f8c81d9527495abafeefed91051df2), PyTorch ROCm | Selected pre-deployment; community mirror of retracted Microsoft weights, so provenance risk remains explicit |

## Operating rules

- Uncensored rows are direct-address/manual only. They generate hypotheses;
  evidence-bearing models or humans judge them.
- The coder pool exposes individual model IDs. Ensemble policy belongs in the
  caller and must preserve each response and attribution.
- The 8B OCR model drains by default. The 32B model is conditional refinement,
  not a permanently co-resident second server.
- DeepSeek V4 is fleet-exclusive. Both nodes must drain other GPU work before a
  DS4 session.
- Audio, image, and video generation remain parked and have no roster entries.
