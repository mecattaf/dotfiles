# Local AI as appliances

The fleet provides a set of bounded appliances, not one undifferentiated LLM
daemon. Each appliance owns a workload, an inference implementation, immutable
model identity, resource class, and an explicit caller boundary.

## Deployment state

The old all-or-nothing `downloadAllModels` gate is gone. A model reaches a host
through exactly one of four mechanisms, and only the coordinator uses any of
them:

1. `services.local-models.allow` — **served**: the row is rooted in the Nix
   store and gets a llama-swap model.
2. `services.local-models.artifacts` — **rooted**: the payload is rooted in the
   store with no llama-swap row, for the selected Mage inference set and the
   speech snapshots whose modality-specific runtimes would be misrepresented as
   llama-swap models.
3. Runtime-owned rosters — FastFlowLM's ad-hoc tags plus the request-scoped
   `utility` slot, and Voxtype's Parakeet snapshot. Nix declares the allowed
   identity; the tool owns the files. No NixOS service starts or retains an FLM
   model, and the exact roster renders to `/etc/local-models/fastflowlm.json`.
4. Everything else in the catalog is **cataloged only** and downloads nothing.

[`model-roster.md`](model-roster.md) is the authoritative split across those
four states; the [coordinator decision](deployment-decisions-2026-07-29.md)
carries the placement ledger and storage totals.

## Hugging Face metadata CLI

Tom's declarative Home Manager profile provides `hf` through
`pkgs.huggingface-cli`; authenticated access remains coordinator-only. Its
underlying `huggingface-hub` package is version 1.16.0 from the locked
`nixpkgs` input, and the flake smoke pins that expected version so a future
lock update requires an intentional review.

Public repository metadata needs no credential. This example requests only the
pinned revision record and sibling names:

```console
hf models info unsloth/Qwen3.6-35B-A3B-MTP-GGUF \
  --revision 5bc3e238d916f48a861bac2f8a1990a0e9b7e98d \
  --expand sha,siblings \
  --format json
```

For gated or private metadata, create a read-only token and enter the raw token
as an agenix secret:

```console
nix develop -c agenix -e secrets/huggingface-token.age
```

`secrets.nix` limits that secret to the coordinator recipients, and
`modules/secrets.nix` decrypts it as
`/run/agenix/huggingface-token`. The `hf` wrapper reads that file into
`HF_TOKEN` only for the child process. It does not run the CLI login flow or
copy plaintext into the Nix store, repository, activation output, or
`$HF_HOME`. This change intentionally carries no token or ciphertext; the
secret declaration becomes active only after the operator provisions the
encrypted file.

Metadata inspection stops at API records such as revisions, tags, sibling
names, and LFS metadata. Monthly Tally research may update catalog candidates,
but it cannot add them to the coordinator allowlist or initiate downloads. Host
activation materializes only the separately reviewed selections.

The targeted smoke check runs `hf --version` and the metadata command against a
local API fixture, then compares the complete isolated `$HF_HOME` manifest
before and after:

```console
nix build .#checks.x86_64-linux.huggingface-cli-smoke --no-link
```

## Appliance map

| Appliance | Selected implementation | Serving boundary | State |
|---|---|---|---|
| Streaming speech-to-text | Voxtype with `parakeet-unified-en-0.6b` | Coordinator-only systemd user service; local ONNX Runtime/MIGraphX on gfx1151 | Model download is an idempotent service pre-start step. |
| Document OCR/RAG | Qwen3-VL 8B primary, 32B refine, Qwen3 Embedding 8B, Qwen3-VL Embedding 8B | Coordinator llama.cpp ROCm behind llama-swap | Active coordinator allowlist; text and multimodal embedders are complementary. |
| Shared text and coding | Qwen 3.6 35B-A3B and stock 27B, both UD-Q8_K_XL with integrated MTP; Gemma 4 26B Q8 with matched MTP | Coordinator Vulkan behind llama-swap | Active coordinator allowlist. Qwen3-Coder-Next remains cataloged only. |
| Computer use | Fara 1.5 27B/9B/4B, each Q8_0 plus matched BF16 projector | Coordinator ROCm behind llama-swap | Active coordinator allowlist; three sizes for the latency/quality tradeoff. |
| Application utility slot | FastFlowLM Qwen3 4B behind the stable ID `utility` | `utility-model` wrapper; one start/request/stop cycle per request | Callers never name the concrete model. Projected from the catalog, not from `services.npu-llm.models`. |
| Ad-hoc NPU inference | FastFlowLM Gemma 4 E4B and GPT-OSS 20B | Direct, ad-hoc `flm run <model>` | Installed on coordinator; no model server starts at boot and idle residency is zero. |
| Call transcription + diarization | Microsoft VibeVoice-ASR | Future dedicated PyTorch/ROCm batch service | BF16 payload and tokenizer are Nix-rooted on coordinator; service remains future work. |
| Text-to-speech | VibeVoice Large community mirror | Future dedicated PyTorch/ROCm batch service | BF16 payload and tokenizer are Nix-rooted on coordinator; mirror risk remains recorded. |
| Image generation and editing | Mage-Flow 4B Turbo generation/editing pair | Direct upstream `MageFlowPipeline`, CLI, or Gradio boundary | Four-step snapshots are selected; Base and RL are omitted. gfx1151/ROCm runtime packaging and smoke remain pending. |
| General image/video understanding and proactive streaming | Microsoft Mage-VL BF16 | Offline Transformers; future custom Mage-VL SGLang branch behind llama-swap | Immutable complete snapshot selected; no runtime row until that SGLang branch is packaged and proven on gfx1151/ROCm. |

## Text classes

- **Utility:** the stable ID `utility` resolves to FastFlowLM Qwen3 4B at 32768
  context, started and stopped around each request.
- **Small and fast:** `gemma4-it:e4b` and `gpt-oss:20b` remain available on
  the coordinator NPU through an explicit `flm run <model>`. FastFlowLM owns the runtime
  files and releases model residency when the command exits.
- **Daily general:** Qwen 3.6 35B-A3B UD-Q8_K_XL with integrated MTP on
  Vulkan.
- **Coder:** stock Qwen 3.6 27B UD-Q8_K_XL with integrated MTP and Gemma 4
  26B A4B IT Q8_0 plus its Q8_0 MTP head are active on coordinator.
  Qwen3-Coder-Next is retained only as catalog metadata.
- **Uncensored:** none are materialized. All three rows are `candidate` and
  absent from the allowlist; see the operating rules in
  [`model-roster.md`](model-roster.md) for the standing disposition.

## Routing and scheduling boundaries

Managed OpenAI-compatible LLM and VLM calls enter through llama-swap. Its
command-managed GPU backends retain the normal load/unload boundary. FastFlowLM
is deliberately separate: ad-hoc NPU work invokes `flm run <model>` directly,
and there is no persistent FLM endpoint. Mage-Flow is likewise direct because
its upstream interface is a diffusion pipeline, not an OpenAI-compatible model
server. Mage-VL may enter llama-swap only through upstream's custom SGLang
server after that exact backend is packaged and verified on ROCm.
Modality-specific speech services keep their own declared endpoints.

Tally schedules, serializes, and proves the monthly community review described
in [`monthly-workflow.md`](monthly-workflow.md). Historical notes do not define
the current architecture.

## Sources of truth

1. [`../../lib/local-models.nix`](../../lib/local-models.nix) owns immutable
   artifact and deployment metadata; the large directory-preserving Mage file
   manifests are factored into
   [`../../lib/mage-models.nix`](../../lib/mage-models.nix).
2. [`../../modules/local-models.nix`](../../modules/local-models.nix) projects
   only the command-managed coordinator allowlist into the Nix store and llama-swap;
   runtime appliances never become proxy peers.
3. [`../../modules/npu-llm.nix`](../../modules/npu-llm.nix) validates the
   explicit FastFlowLM roster and writes its non-resident runtime manifest.
4. [`mage.md`](mage.md) records the selected Mage download set, deduplicated
   storage cost, upstream invocation contract, and serving boundary.
5. [`deployment-decisions-2026-07-29.md`](deployment-decisions-2026-07-29.md)
   is the authoritative active placement and storage ledger.
6. [`model-roster.md`](model-roster.md) is the authoritative human-readable
   split: served, rooted, runtime-owned, and cataloged-only, including the
   speech and NPU appliances that do not belong in the llama-swap catalog.
7. [`tallies/`](tallies/) records accepted roster rationale. The monthly update
   bot advances its exact research-source pins in `sources.json`; its advisory
   summary remains visible in the corresponding pull request.
8. [`dual-node-inference-lessons.md`](dual-node-inference-lessons.md) preserves
   the operational lessons from the retired dual-node ds4 cluster. It is
   history, not a deployment target.

[`../old/`](../old/) is now an archival stub. The material it held is
recoverable from Git history, and the stub records how.
