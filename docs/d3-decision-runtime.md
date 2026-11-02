# D3-Ultra decision appliance

The selected implementation is **D3-Ultra BF16 with native `vllm-srun`**, the
vLLM Semantic Router project's dedicated decision worker. It is not the stock
vLLM server. Tom selected this single implementation on 2026-11-02; stock
vLLM and libstrix were comparison experiments and have been removed from the
runnable dotfiles configuration. Their measurements remain in the
[qualification archive](d3-qualification/2026-11-01/README.md).

## Model store and deployment

The existing model store owns the complete byte-level definition:

- `lib/decision-models.json`: artifact `d3-ultra-bf16`, official revision
  `52ba9e7a00402f9560c7fba8c039608e7ddee7fb`, 36 files and 52,199,363,315 bytes,
  with exact sizes and SHA-256 hashes. `lib/local-models.nix` imports it into
  the same catalog as the other local models.
- NAS Library: `/mnt/nas/models/weights/d3-ultra-bf16/`. The existing
  `library-fetch` acquisition service owns upstream downloads.
- Coordinator loan: `/var/lib/local-models/d3-ultra-bf16/`, a real local
  directory populated by the explicit, verified `local-models-borrow`
  transaction. The runtime uses this directory, not a Hub model name or an
  `/etc/local-models/artifacts/...` symlink.
- `hosts/strix-coordinator/default.nix`: enables the native service and its
  llama-swap demand route. The module adds the artifact to
  `services.local-models.requirements.d3-decision`; it therefore appears in
  `/etc/local-models/wanted.json` without a second manually maintained list.

The BF16 snapshot was acquired and loaned on 2026-11-01, with every file hash
verified. A 2026-11-02 close-out check found all 36 files at their declared
sizes in both locations. Builds, activation, boot and worker startup never
fetch or copy model weights. No quantized or Gemma-derived decision model is
part of this deployment.

For a future explicit acquisition/loan transaction, use the existing commands:

```sh
# On NAS: acquire missing catalog bytes into the canonical Library.
sudo systemctl start library-fetch
# On coordinator: inspect, then explicitly apply the wanted loan set.
sudo local-models-borrow --dry-run
sudo local-models-borrow --yes
```

These are operator actions, not prerequisites to repeat for every request.
`local-models-prune` is a separate explicit transaction; it is never invoked
by this worker. See the [model-store runbook](nas/model-archive.md).

## Use the decision model

The normal entry point is the existing llama-swap on
`http://strix-coordinator:8731`. Its `d3-ultra` route preserves the native
System One request and response; Gufo serves the other declared models on
the same gateway.

```sh
curl --fail --show-error --max-time 1200 \
  http://strix-coordinator:8731/upstream/d3-ultra/v1/systemone \
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

Choice and Score answers contain probability maps; Noul returns `noul`, the
probability of true. Box and Track use the same native worker. Native
`/v1/decisions` is also available under the same upstream prefix. This is a
decision API, not a chat-completions endpoint.

An explicit D3 request releases the previous backend before loading D3. A
later Gufo request swaps back. The default group permits one loaded backend
at a time; D3 has a ten-minute idle TTL. The launcher waits for both its
worker and memory guard to exit before releasing its supervised process.
The deployed D3-to-Gufo transition, including full worker reaping, was
qualified on 2026-11-01.

First use pays model loading (about 30 seconds in the qualified warm-page-cache
run); request time after loading is separate. A cold-load timeout of 1,200
seconds accommodates loading without turning ordinary monitoring into inference.

Routine probes do not load a model:

```sh
curl --fail http://strix-coordinator:8731/health
curl --fail http://strix-coordinator:8731/v1/models
curl --fail http://strix-coordinator:8731/running
```

An empty running list means the models are unloaded, not broken. Backend
ports are assigned by llama-swap and bound to loopback. Direct D3/Gufo units
are manual diagnostics, have no boot target and conflict with llama-swap;
application callers use the proxy. Direct D3 port 8733 is not opened in the
firewall.

The gateway scope is D3 plus Gufo model serving. Tom explicitly left the
existing qualified speech utility, one-off call diarization and infrequent
Immich ML path outside this change. The production speech voice remains on
its qualified engine until its separately planned move to Gufo TTS.

## Runtime and qualification

The native package pins Semantic Router commit
`62c4f39e35aa2dfe929eb18223a7509ebeff6563` (`vllm-srun` 0.2.0), with AMD's
stable PyTorch 2.13 / ROCm 10.1 stack and matching Triton 3.8 and gfx1151
device kernels. `pkgs/vllm-srun/rocm10-wheels.json` pins every official wheel
by SHA-256; the existing Nix wheel builder assembles them offline. This
D3-specific bundle replaces the July ROCm 7.15 snapshot without changing the
other engines' dependency sets. This follows the native-runtime approach
established on gfx1151 by
[Semantic Router PR 5308](https://github.com/vllm-project/semantic-router/pull/5308).
Ultra's prompt, prefix-bidirectional attention and answer contract are handled
by this native worker. Hugging Face checkpoint Python is not imported. The wrapper supplies a pinned
C compiler for Triton’s HIP launcher. JIT shared objects use the service’s
private `/tmp/d3-decision-jit`, because DynamicUser mounts its persistent
CacheDirectory with `noexec`; Hub metadata remains in the persistent cache.

The initial appliance permits one sequence and 4,096 batched tokens, with a
90 GiB estimated engine budget. Startup requires 80 GiB host MemAvailable;
the launcher terminates its worker below a 12 GiB reserve. Proxy hardening
retains DynamicUser, read-only model paths and service-owned writable caches
for PyTorch/Triton; executable mappings are permitted for JIT code.

The retained 2026-11-01 BF16 qualification used the earlier PyTorch 2.11 /
ROCm 7.15 bundle. It returned stable valid distributions on gfx1151 over
three repeats per request. Median request latencies were 0.979 s for code,
1.009 s for a JSON billing ticket and 4.964 s for a document summary. The
service peaked at 53.0 GiB. Single-question calibration, a synthetic image
Box and a short synthetic video Track also passed. These are functional
checks, not a model-quality benchmark; full 131k context and parity with the
release's reference GPU were not qualified. The worker reports approximate
numerics and no matched release golden reference.

[Native qualification receipt](d3-native-qualification-2026-11-01.json) ·
[retained comparison and reproduction](d3-qualification/2026-11-01/README.md).
`tests/d3-decision` covers the actual worker on a tiny CPU fixture, hardened
API routing, no load from monitoring, model eviction, worker reaping and the
native-only production policy. Runtime-sensitive experiments run through
`runtime-test` on coordinator; NAS remains the agent and credential host.
