# D3 Ultra runtime

`services.d3-decision` serves the `d3-ultra-bf16` snapshot through the native
`vllm-srun` worker from vLLM Semantic Router. It is a separate engine module
beside Gufo. The worker answers typed decisions on `/v1/systemone`; it does
not generate chat completions.

The deployment is registered as `d3-ultra` in the existing llama-swap
supervisor. It shares the default single-resident-model group with Gufo:
an explicit D3 request releases the previous backend, loads D3, and the worker
is stopped after ten idle minutes. A later Gufo request swaps back. Rebuilding
starts no GPU workload. `/health`, `/running` and `/v1/models` on the proxy
remain the routine probes; an `/upstream/...` request deliberately wakes its
backend.

After the NAS Library fetch and explicit loan transaction have completed:

```sh
curl --fail --show-error http://strix-coordinator:8731/upstream/d3-ultra/v1/systemone \
  -H 'Content-Type: application/json' --data-binary '{
    "model": "d3-ultra",
    "state": {"ticket": "My card was charged twice for one order."},
    "questions": {
      "team": {
        "type": "choice",
        "instructions": "Which team should handle this ticket?",
        "criteria": {"billing": "Payments and refunds", "shipping": "Deliveries"}
      },
      "urgent": {"type": "noul", "instructions": "Does this need an urgent reply?"}
    }
  }'
```

Use the native response as returned: Choice/Score have probability maps; Noul
returns `noul`, the probability of true. This path preserves JSON states,
question types and multimodal requests without translating them to chat.
Native `/v1/decisions` is also available under the same upstream prefix.

`d3-decision.service` remains a manual diagnostic route on loopback port 8733.
Starting it conflicts with llama-swap, as the direct Gufo diagnostic units do.
Normal use goes through the proxy instead. The shared launcher refuses to run
while a standalone Gufo, DS4, image or TTS service owns the GPU. It requires
80 GiB host `MemAvailable` before loading and terminates its worker if that
falls below 12 GiB. Requests default to one sequence and 4,096 batched tokens;
these are initial appliance limits, not a claim of the model's full 131k
context being qualified on this host. The worker's estimated memory budget is
90 GiB, with systemd memory limits as a second boundary.

The launcher always receives the real directory
`/var/lib/local-models/d3-ultra-bf16`, with offline flags and an empty service
home. It checks every catalog file's size before starting; native package
verification checks the manifest and scored identity before loading. Code
bundled with the Hugging Face checkpoint is never imported by this engine.
Builds and service startup fetch no model weights. The runtime accepts a real
directory, not the `/etc/local-models/artifacts/...` symlink.

## Reproducibility and current alternatives

- Runtime: semantic-router commit
  `62c4f39e35aa2dfe929eb18223a7509ebeff6563`, package `vllm-srun` 0.2.0.
  [Upstream worker](https://github.com/vllm-project/semantic-router/tree/62c4f39e35aa2dfe929eb18223a7509ebeff6563/src/model-runtime).
- GPU stack: the existing `nix-strix-halo` flake input's pinned CPython 3.13
  TheRock PyTorch/Triton bundle for gfx1151, with its own library search path.
  The package adds no second nixpkgs PyTorch/ROCm stack. Its build uses cached
  Python dependencies rather than compiling PyTorch or vLLM.
- The worker's stale built-in Ultra Hub revision is bypassed by passing the
  explicit catalog directory. Manifest and identity verification remain
  enabled. [Upstream issue 5642](https://github.com/vllm-project/semantic-router/issues/5642).
- The stock nixpkgs pin has vLLM 0.16.0 and predates Decision 3 support. Newer
  stock vLLM supports earlier D3 checkpoints, but Ultra's `prefix_bidir`
  attention requires additional support. Do not substitute causal attention
  to make it load: that changes the model. The pinned native worker implements
  Ultra's state-once layout, header-v1 prompts, temperature table, Box and
  Track. [vLLM prefix-bidir work](https://github.com/vllm-project/vllm/pull/62584).
- The official FP8 checkpoint requires FP8 matrix units; its native loader
  accepts ROCm gfx942/gfx950, excluding Strix gfx1151. BF16 is the initial
  production candidate; official INT4 is a separate qualification candidate.
  [Native quantized loader](https://github.com/vllm-project/semantic-router/blob/62c4f39e35aa2dfe929eb18223a7509ebeff6563/src/model-runtime/vllm_srun/engines/native/quantized.py).
- libstrix registers a `vllm.general_plugins` entry point. That hook is not
  loaded by `vllm-srun`; installing it beside this worker would not create a
  meaningful A/B test. Its individual GDN operators may be reusable through a
  future native accelerator adapter, but its causal attention kernels must
  not replace Ultra's prefix-bidirectional attention. A patched vLLM/libstrix
  experiment is a distinct path and needs typed-decision numerical parity
  before performance comparisons. [libstrix](https://github.com/asf0/libstrix/tree/d7862c63cf7fa453780032b966363b6fb5d95121).

The hardware precedent is [Semantic Router PR 5308](https://github.com/vllm-project/semantic-router/pull/5308):
the earlier D3 BF16 model ran 231 requests on gfx1151 without a failed
request. It retained gfx1151 rocBLAS/hipBLASLt libraries and supplied the
missing causal-convolution device code. Ultra adds prefix-bidirectional
attention and its own prompt/readout contract, so that earlier result does
not qualify Ultra by itself. The native package above retains the existing
Strix-capable PyTorch stack and implements Ultra's contract explicitly.

### Quantizations checked on 2026-11-01

Sizes are checkpoint/package download sizes, not peak loaded memory.

| Release | Approximate size | Strix gfx1151 assessment |
| --- | --- | --- |
| [Official BF16](https://huggingface.co/vllm-sr/d3-ultra) | 52.2 GB | Initial reference; full local GPU qualification below. |
| [Official FP8](https://huggingface.co/vllm-sr/d3-ultra-FP8) | 31.9 GB | Released W8A8 loader accepts gfx942/gfx950, excludes gfx1151. |
| [Official INT4](https://huggingface.co/vllm-sr/d3-ultra-INT4) | 17.6 GB | Portable BF16 dequantization path; a later memory-saving candidate, not a proven speedup. |
| [Official NVFP4](https://huggingface.co/vllm-sr/d3-ultra-NVFP4) | 17.3 GB | Released path requires NVIDIA Blackwell. |
| [Community GPTQ W4A16](https://huggingface.co/evanrodgers/d3-ultra-W4A16-GPTQ) | 16.1 GB | Separate unqualified conversion; no fleet measurement. |
| [Community GGUF](https://huggingface.co/magnitudedev/d3-ultra-GGUF) | Q4 15.8 GB plus 0.93 GB projector | Magnitude-specific decision metadata; does not establish Gufo support. |

libstrix's FP8 weight kernels emulate a different W8A16 operation. Enabling
them does not make the official D3 W8A8 loader support gfx1151. No quantized
weights are borrowed by this initial BF16 declaration.

## Validation

`tests/d3-decision/smoke.py <vllm-srun>` runs the installed native worker over
HTTP against an upstream tiny random-weight Ultra-shaped fixture on CPU. It
checks the actual prefix-bidirectional path, Choice/Noul/Score responses and
repeatability. The fixture deliberately embeds checkpoint code that raises
on import, so success also checks that the native loader never executes it.
This test checks runtime integration, not trained-model quality or GPU speed.

`tests/d3-decision/test_proxy.py` exercises the real llama-swap executable
with disposable native-decision and text backends: no load from ordinary
monitoring, native body/path preservation, model eviction and idle unload.

Run runtime experiments through `runtime-test` on the target, with the source
staged under `/var/lib/microvms/` and commands sent through `fleet-exec`.
Production-model GPU qualification requires a coordinated idle window and
restoring the established Gufo demand endpoint afterward.

On 2026-11-01 the installed package passed the tiny Ultra CPU fixture through
a separate real systemd/llama-swap service with DynamicUser, PrivateUsers,
ProtectHome, ProtectSystem=strict, RestrictNamespaces and the production
SystemCallFilter. The private cache was writable by the dynamic UID. Four
Choice/Noul/Score requests retained the same probabilities on repetition;
the service's memory peak was 598,544,384 bytes. This qualifies the service
boundary, not production model accuracy or throughput. The upstream fixture
writer makes safetensors files mode 0600; test copies need mode 0644, as the
production borrow transaction already sets.

The installed native stack is PyTorch
`2.11.0+rocm7.15.0a20260719` and Triton
`3.7.1+git0263a6a6.rocm7.15.0a20260719`. It differs from the model release's
reference PyTorch build. A small BF16 matrix-multiply probe passed both in the
GPU-enabled runtime-test wrapper and under the actual service hardening:
AMD Radeon 8060S, gfx1151, exact expected result and a successful exit. The
hardened probe peaked at 473.5 MiB. The full-model results below are separate
from this hardware probe.

`tests/d3-decision/benchmark.py` records a bounded real-model smoke workload:
code, a JSON billing ticket and a short document summary, each with
Choice/Noul/Score questions. It validates finite normalized probabilities,
records repeated-answer drift and argmax stability, and writes request
digests, the model card, cold readiness time, request latencies, host memory
and supplied provenance to JSON. It starts or stops no service:

```sh
runtime-test -- python3 tests/d3-decision/benchmark.py \
  --base-url http://127.0.0.1:8731/upstream/d3-ultra --model d3-ultra \
  --output /var/lib/microvms/d3-native-result.json \
  --provenance 'Record the exact runtime, model revision and host generation here'
```

The complete pinned BF16 model passed native GPU qualification on
strix-coordinator on 2026-11-01, through a separate real llama-swap service
with the same hardening and lifecycle-aware launcher. The verified 36-file,
52,199,363,315-byte NAS loan was used directly. Cold-process readiness took
30.4 seconds; the filesystem page cache was warm from the verified loan and
was not dropped. The service peaked at 56,911,736,832 bytes (53.0 GiB), with
one sequence and a 4,096-token batch budget.

| Request | Questions | Repeats | Median latency |
| --- | --- | --- | --- |
| Code task | Choice, Noul, Score | 3 | 0.979 s |
| JSON billing ticket | Choice, Noul, Score | 3 | 1.009 s |
| Short document summary | Choice, Noul, Score | 3 | 4.964 s |

All nine text requests returned valid distributions and exactly repeated
their probabilities and argmax choices. A separate single-question Choice
exercised Ultra's 1.046 temperature path. A synthetic 256×256 red square was
recognized, with a valid Box at 1.028 seconds; a two-second, four-frame
synthetic video returned two valid Track observations at 1.351 seconds.
These are functional checks on simple inputs, not an accuracy benchmark or
a Jev evaluation. The model's long-context capacity was not exercised.
The native runtime reports `numerics: approximate` and no matched release
golden reference for this local model identity; deterministic results here
do not establish parity with the release's MI325X reference build.

Both temporary proxy units were stopped and Gufo was restored and passed
`/ready` after each window. No NixOS generation was activated. The compact
[qualification receipt](d3-native-qualification-2026-11-01.json) records
model/runtime identities, typed answers, timings, memory and restoration.
`tests/d3-decision/qualify_multimodal.py` preserves the supplementary request
capture workflow. Verify production deployment separately using the host's
configuration revision and the proxy probes above.

## Patched vLLM and libstrix comparison

Both experimental variants also loaded the complete BF16 model on this host
and served the same nine text/JSON requests. The Nix appliance backports
prefix-bidirectional attention and Ultra's prompt, temperature and native
answer contract. Native remains the default: it supports Box/Track and had
the lowest measured latency in this small workload.

| Request | Native | Stock vLLM | vLLM with libstrix |
| --- | --- | --- | --- |
| Code task | 0.979 s | 1.593 s | 1.476 s |
| JSON billing ticket | 1.009 s | 1.627 s | 1.486 s |
| Short document summary | 4.964 s | 8.854 s | 7.734 s |

These are median request latencies, excluding server startup. libstrix
reduced stock vLLM's medians by 7–13%; it still took 1.47–1.56 times the
native worker's latency. Logs confirm dispatch into libstrix convolution,
post-convolution and GEMM kernels. Its causal attention replacements stayed
disabled in order to preserve Ultra's prefix-bidirectional attention.

All repetitions were stable and no argmax decision changed across engines.
The maximum absolute probability difference from native was 0.006314 for
stock and 0.003214 with libstrix. This is functional agreement on synthetic
inputs, not a model-quality or broad numerical-parity evaluation. The two
engines also use different pinned Torch/ROCm builds.

The standard native worker does not load libstrix's vLLM plugin hook. That,
the measured results and the complete native API are why libstrix is not
used in the default appliance. The disabled manual experiment remains
available through `nix build .#d3-vllm-experiment` on compute, followed by
`d3-vllm-experiment baseline|libstrix` in a coordinated GPU window.
[Package, patches, hardening fixes and reproduction](../pkgs/vllm-d3/README.md)
and [retained comparison](../tests/d3-vllm-experiment/results/2026-11-01/comparison.json).
