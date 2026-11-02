# D3-Ultra comparison evidence, 2026-11-01

These are retained measurements of the native BF16 worker and the retired
stock-vLLM/libstrix comparison. They are historical evidence, not alternate
deployment options. On 2026-11-02 Tom selected native `vllm-srun` as the one
D3 implementation, independent of small speed/leaderboard differences.

- `native.json`, `baseline.json`, `libstrix.json`: complete request/answer and
  timing captures, with the original provenance.
- `receipt.json`: pinned model, image, GPU stack and kernel-selection details.
- `comparison.json`: computed differences and median request latencies.
- `compare.py`: standalone comparison helper; no model execution or downloads.

Recompute the retained comparison without a GPU or model server:

```sh
python3 compare.py --native native.json --baseline baseline.json \
  --libstrix libstrix.json --output /tmp/d3-comparison.json
```

The retired Nix appliance, exact patches and experiment instructions remain
available in [Git history at the qualified commit](https://github.com/mecattaf/dotfiles/tree/48e817318be80f83db39b240688a3f865b4b336e/pkgs/vllm-d3).
The current [runbook](../../d3-decision-runtime.md) describes the selected
runtime, NAS Library, coordinator loan and llama-swap request path.
