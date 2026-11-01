D3-Ultra on the Strix GPU
========================

The full-feature reference is the separate native `vllm-srun` worker. This
package is an experimental vLLM comparison with a real D3 answer-code head
and `/v1/systemone`, supporting Choice, Noul and Score. Box and Track stay on
the native worker.

The package pins the publisher's already compiled gfx1151 vLLM/libstrix image,
extracts it once during a Nix build, checks both source revisions and every
Python file being changed, then applies three reviewable Nix patches. The
result is an immutable root filesystem launched with bubblewrap. Starting it
does not fetch an image, install Python packages, patch files, or download
weights. A real NAS Library loan directory is mounted read-only.

This fallback avoids pretending the installed Nix vLLM package is current:
nixpkgs provides 0.16.0, the existing TheRock overlay provides 0.25.1, and its
dependency set has Transformers 5.5.4, tokenizers 0.22.2 and Hub 1.16.0. The
needed vLLM source requires at least 5.16.1, 0.23.2 and 1.31.0 respectively,
plus newer xgrammar and MCP. Reusing old C++ extensions with that source and
a different Torch build would not establish ABI compatibility. The pinned
appliance instead keeps Python 3.14, Torch 2.14.0, ROCm 10.1 and its compiled
extensions together. Only existing Python model/config/request interfaces
change; no new compiled operation is introduced.

Patches
-------

`0001-d3-prefix-bidir.patch` backports the pure Python implementation of
[vLLM PR 62584](https://github.com/vllm-project/vllm/pull/62584), exact head
`dfa830766b0d082870ff2f64b0fdc5ab0daaab49`, to the image's fork revision
`efdfdf954bd7d3ae7dfa2ab4702b2317f9d20c42`. It gives full-attention layers
separate bidirectional state/question ranges while linear layers stay causal.
It preserves the newer fork's multimodal clamp/span handling. The launcher
forces Model Runner V2 and disables prefix caching and chunked prefill, which
the backported implementation has not qualified. A boolean cannot masquerade
as a one-token state length.

`0002-d3-ultra-layout-temperature.patch` supplies the Ultra features missing
from that PR: the complete question-list header inside the text-only state
block, Score levels in that header, and per-request temperature calibration.
One question uses 1.046, larger requests use 1.0. Request-local values preserve
concurrent requests. JSON instructions and option descriptions keep JSON
serialization instead of Python's `str(dict)`. Media requests follow the
checkpoint's header-free path.

`0003-d3-systemone-answer.patch` preserves D3's entropy-based Choice/Score
confidence, canonical Score legends, and scalar Noul answer. The generic vLLM
label-confidence convention would otherwise change the API even with identical
model probabilities.

The reference is the official
[Ultra release](https://huggingface.co/vllm-sr/d3-ultra/tree/52ba9e7a00402f9560c7fba8c039608e7ddee7fb).
The CPU checks compare the patched class with its pinned `d3_format.py`;
they do not establish GPU numerical parity or multimodal correctness.

libstrix A/B
------------

Both variants use the identical root filesystem, compiled extensions, model
and patches. `D3_VLLM_LIBSTRIX=0` sets `STRIX_DISABLE=all` for the vLLM baseline.
`D3_VLLM_LIBSTRIX=1` enables libstrix except `attn_prefill,attn_decode`. Those
attention swaps include causal-only HIP kernels and a substituted Triton
implementation; Ultra keeps the upstream PrefixLM-aware attention in both
variants. GDN and linear operations can still use libstrix. This is a
conservative experiment, not a claim that all libstrix kernels accelerate D3
or that the base-Qwen generative benchmarks transfer to decision scoring.

The standard native `vllm-srun` worker does not load `vllm.general_plugins`,
so installing libstrix beside it would have no effect. Individual exported
libstrix GDN operators could be reused by a future native accelerator adapter;
their compatible shapes alone do not prove layout, state or numerical parity.

Example invocation after building on compute:

```sh
D3_CACHE_ROOT=/var/cache/d3-vllm-baseline D3_VLLM_LIBSTRIX=0 \
  d3-vllm serve /var/lib/local-models/d3-ultra-bf16 \
    --served-model-name d3-ultra --host 127.0.0.1 --port 8898 \
    --dtype bfloat16 --max-model-len 4096 --max-num-seqs 1 \
    --max-num-batched-tokens 4096 --gpu-memory-utilization 0.65 --enforce-eager
```

Stop the native worker before loading this one. Compare `/v1/systemone`
answers and option probabilities against native BF16 first, then repeat the
same inputs with libstrix enabled. Use separate writable compile caches for
the two variants. Performance comparisons must report warm-up separately,
weight dtype, input lengths, request concurrency, question counts, changed
decisions and maximum probability differences.

Service integration
-------------------

The launcher needs user, PID, IPC and UTS namespaces and executable mappings.
llama-swap's default `RestrictNamespaces=true` and privileged-syscall filter
block this; do not claim an ordinary unmodified DynamicUser unit can run it.
Qualify in a separate experimental unit first and scope any necessary
namespace/syscall overrides to explicitly enabled experimental routes. Keep
the production native D3 route unchanged until the comparison succeeds.

The imported `services.d3-vllm-experiment` module defaults to disabled. Enabling
it installs a manual `d3-vllm-experiment.service`, with no boot target, socket
or timer, and the explicit `d3-vllm-experiment baseline|libstrix` CLI. The unit
binds only `127.0.0.1:8734` and uses the same existing BF16 loan. It refuses to
start while a declared GPU owner is active; it never stops another service.
The production proxy and native D3 route keep their existing configuration.

For supervised GPU qualification on compute, after the other owner has been
explicitly released, the module's launcher can run inside the runtime wrapper:

```sh
nix build .#d3-vllm-experiment
runtime-test --allow-gpu /dev/dri/renderD128 -- \
  ./result/bin/d3-vllm-experiment baseline
```

Choose the real render node for the host. Repeat with `libstrix` after the
first process has exited. The CLI uses separate writable caches per variant;
no NixOS activation or worker boot target is needed for this manual comparison.

CPU-only appliance imports passed in a transient DynamicUser service with
these namespace and filesystem restrictions, NoNewPrivileges, and no GPU
device mounts: Torch 2.14, all patched D3 classes, and libstrix's 48 registered
kernels loaded successfully. This checks the extension ABI and service setup;
it does not establish GPU answer parity or speed.

No NPU or FastFlowLM path is part of this package.
