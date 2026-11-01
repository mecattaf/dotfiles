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
