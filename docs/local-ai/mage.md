# Microsoft Mage family

Status: selected for declarative coordinator materialization on 2026-07-29.
The source checkout used for the review is `/home/tom/Downloads/Mage` at
`8c94a0ac905167f40b05b09332b78752b7f9fbef`.

## Download set

Microsoft publishes six checkpoints in the upstream
[Mage-Flow model zoo](https://github.com/microsoft/Mage/tree/main/mage_flow#-model-zoo).
The selected inference set keeps only the Turbo checkpoint for each capability,
along with the one unified
[Mage-VL checkpoint](https://huggingface.co/microsoft/Mage-VL). Base is absent
because this host will not train Mage. RL is also absent: its benchmark gain is
small relative to increasing generation from 4 to 20 steps and editing from 4
to 30 steps. The two selected Mage-Flow repositories are pinned to the
`mage-flow-community` Hub duplicates because the original Microsoft model
endpoints stopped resolving publicly. The mirror commits identify themselves
as duplicates of the corresponding `microsoft/Mage-Flow*` repositories.

The Gradio source also contains a `Mage-Flow-SciForma` preset, but it is absent
from Microsoft's released model-zoo table and from the live community mirror.
It is therefore not treated as a released seventh Flow checkpoint.

| Artifact ID | Checkpoint and pinned source | Capability / upstream settings | Logical bytes |
|---|---|---|---:|
| `mage-flow-4b-turbo-bf16` | [`Mage-Flow-Turbo@65bb350`](https://huggingface.co/mage-flow-community/Mage-Flow-Turbo/tree/65bb3500f0da9df6a41ec6383716fc02cf014773) | text-to-image distilled; 4 steps, CFG 1 | 17,507,371,477 |
| `mage-flow-edit-4b-turbo-bf16` | [`Mage-Flow-Edit-Turbo@66df6fa`](https://huggingface.co/mage-flow-community/Mage-Flow-Edit-Turbo/tree/66df6fa1aba5b40cd4120739134292eab9779da3) | instruction editing distilled; 4 steps, CFG 1 | 17,507,371,487 |
| `mage-vl-bf16` | [`microsoft/Mage-VL@5c78cab`](https://huggingface.co/microsoft/Mage-VL/tree/5c78cab61938e73859b63724d9bf5cb88c477eaa) | image/video understanding, both codec paths, and proactive streaming gate | 10,848,275,030 |

The three complete snapshots contain **45,863,017,994 logical bytes (45.86 GB /
42.71 GiB)**. The two Flow repositories share 40 byte-identical files,
including their text encoder, VAE, scheduler, and showcase assets. Their shared
set is 9,275,798,241 bytes. Snapshot fetches use repository-relative output
paths but content-derived Nix store names, so byte-identical files converge on
the same fixed-output store paths even when Mage-VL places them elsewhere. The
actual unique Mage closure is therefore **36,583,914,927 bytes (36.58 GB /
34.07 GiB)** before small derivation and symlink-farm metadata.

`microsoft/Mage-ViT` is deliberately not a separate download. Upstream
describes it as the pretraining-only visual encoder, without joint VLM
training. The selected Mage-VL checkpoint already supplies the deployable
understanding and streaming capabilities; Mage-ViT would add a research
fine-tuning starting point, not another serving capability.

## Declarative paths

`services.local-models.artifacts` roots every selected snapshot in the
coordinator system closure. After activation, each is available by stable
artifact ID under `/etc/local-models/artifacts/`. Upstream-compatible aliases
also appear under `/etc/local-models/snapshots/`:

```text
/etc/local-models/snapshots/Mage-Flow-Turbo
/etc/local-models/snapshots/Mage-Flow-Edit-Turbo
/etc/local-models/snapshots/Mage-VL
```

The aliases preserve the names expected by Mage-Flow's `MAGEFLOW_HF_DIR`
support. File paths, byte sizes, SHA-256 values, and immutable Hub revisions
live in [`../../lib/mage-models.nix`](../../lib/mage-models.nix). Nix
materialization preserves nested repository paths instead of flattening
duplicate names such as `config.json`.

## Runtime boundaries

### Mage-Flow

Mage-Flow is a Diffusers-style Python pipeline, not an LLM server and not an
OpenAI-compatible endpoint. It must **not** be registered as a llama-swap
model. Upstream loads a local snapshot with `MageFlowPipeline.from_pretrained`
or the `mage-flow` / `mage-flow-edit` CLIs. The Gradio app accepts the alias
root directly:

```console
export MAGEFLOW_HF_DIR=/etc/local-models/snapshots
mage-flow-app
```

Equivalent explicit CLI paths are:

```console
mage-flow \
  --prompt "A technical cutaway illustration of a lunar greenhouse" \
  --model_path /etc/local-models/snapshots/Mage-Flow-Turbo \
  --steps 4 --cfg 1

mage-flow-edit \
  --prompt "Replace the background with a field of sunflowers" \
  --ref /path/to/input.png \
  --model_path /etc/local-models/snapshots/Mage-Flow-Edit-Turbo \
  --steps 4 --cfg 1
```

Turbo checkpoints use four steps and CFG 1. The upstream package currently
requires a recent CUDA-oriented PyTorch stack and separately built
FlashAttention. The coordinator is gfx1151/ROCm, so this
change downloads and exposes the exact snapshots but does not invent an
unverified service or Python environment. Runtime packaging needs a matched
ROCm smoke before it becomes part of the system profile.

### Mage-VL

The single Mage-VL snapshot covers still images, frame-sampled video,
traditional H.264/HEVC codec processing, neural DCVC-RT processing, and the
event-gated streaming mode. No extra understanding or streaming checkpoint is
needed.

Upstream supports two boundaries:

- Offline Transformers inference loads the local directory with
  `AutoModelForCausalLM.from_pretrained(..., trust_remote_code=True)`.
- Online image/frame inference uses the custom `feat/mage-vl` branch of
  `kcz358/sglang`, which exposes an OpenAI-compatible API.

Only the second boundary belongs behind llama-swap. The existing llama.cpp and
vLLM backends do not implement Mage-VL's custom codec-native architecture, and
the upstream SGLang branch is not yet packaged or proven on gfx1151/ROCm.
Accordingly, `mage-vl-bf16` is a selected appliance payload but not a bogus
llama-swap row. A later runtime change must package that exact SGLang branch,
point `--model-path` at `/etc/local-models/snapshots/Mage-VL`, keep Hub access
offline, and let llama-swap own its load/unload lifecycle.

The neural codec snapshot includes upstream CUDA extension sources and DCVC-RT
weights. Their presence makes the checkpoint complete; it does not constitute
ROCm compatibility evidence.
