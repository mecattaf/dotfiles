# Local AI as appliances

The fleet provides a set of bounded appliances, not one undifferentiated LLM
daemon. Each appliance owns a workload, an inference implementation, immutable
model identity, resource class, and an explicit caller boundary.

## Deployment state

The old all-or-nothing `downloadAllModels` gate is gone. The coordinator has an
explicit `services.local-models.allow` list for command-managed llama-swap
deployments and a separate list for non-llama speech artifacts. FastFlowLM NPU
rows remain runtime-appliance metadata: their existing files may stay under
`~/.config/flm/models`, but no NixOS service starts or retains them. The exact
FLM roster is declared in `services.npu-llm.models` and rendered
to `/etc/local-models/fastflowlm.json`. See the
[current coordinator decision](deployment-decisions-2026-07-29.md) for placement and
storage totals.

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
| Computer use | Fara 1.5 27B Q8_0 plus BF16 projector | Coordinator ROCm behind llama-swap | Active coordinator allowlist. |
| NPU utility | FastFlowLM Gemma 4 E4B and GPT-OSS 20B | Direct, ad-hoc `flm run <model>` | Installed on coordinator; no model server starts at boot and idle residency is zero. |
| Call transcription + diarization | Microsoft VibeVoice-ASR | Future dedicated PyTorch/ROCm batch service | BF16 payload and tokenizer are Nix-rooted on coordinator; service remains future work. |
| Text-to-speech | VibeVoice Large community mirror | Future dedicated PyTorch/ROCm batch service | BF16 payload and tokenizer are Nix-rooted on coordinator; mirror risk remains recorded. |
| Audio, image, and video generation | None | None | Parked. Stable Diffusion is explicitly outside the local-LLM route. |

## Text classes

- **Small and fast:** `gemma4-it:e4b` and `gpt-oss:20b` remain available on
  the coordinator NPU through an explicit `flm run <model>`. FastFlowLM owns the runtime
  files and releases model residency when the command exits.
- **Daily general:** Qwen 3.6 35B-A3B UD-Q8_K_XL with integrated MTP on
  Vulkan.
- **Coder:** stock Qwen 3.6 27B UD-Q8_K_XL with integrated MTP and Gemma 4
  26B A4B IT Q8_0 plus its Q8_0 MTP head are active on coordinator.
  Qwen3-Coder-Next is retained only as catalog metadata.
- **Uncensored:** all rows are deferred and remain catalog-only.

## Routing and scheduling boundaries

Managed OpenAI-compatible LLM and VLM calls enter through llama-swap. Its
command-managed GPU backends retain the normal load/unload boundary. FastFlowLM
is deliberately separate: ad-hoc NPU work invokes `flm run <model>` directly,
and there is no persistent FLM endpoint. Modality-specific speech services keep
their own declared endpoints.

Tally schedules, serializes, and proves the monthly community review described
in [`monthly-workflow.md`](monthly-workflow.md). Historical notes do not define
the current architecture.

## Sources of truth

1. [`../../lib/local-models.nix`](../../lib/local-models.nix) owns immutable
   artifact and deployment metadata.
2. [`../../modules/local-models.nix`](../../modules/local-models.nix) projects
   only the command-managed coordinator allowlist into the Nix store and llama-swap;
   runtime appliances never become proxy peers.
3. [`../../modules/npu-llm.nix`](../../modules/npu-llm.nix) validates the
   explicit FastFlowLM roster and writes its non-resident runtime manifest.
4. [`deployment-decisions-2026-07-29.md`](deployment-decisions-2026-07-29.md)
   is the authoritative active placement and storage ledger.
5. [`model-roster.md`](model-roster.md) is the broader human-readable catalog,
   including deferred rows and
   runtime and speech appliances that do not belong in the llama-swap catalog.
6. [`tallies/`](tallies/) records accepted roster rationale. The monthly update
   bot advances its exact research-source pins in `sources.json`; its advisory
   summary remains visible in the corresponding pull request.

The old documentation under [`../old/`](../old/) is evidence, not authority.
