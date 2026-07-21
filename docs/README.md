# Documentation

The current documentation starts here.

| Path | Purpose |
|---|---|
| [`local-ai/README.md`](local-ai/README.md) | Current local-AI appliance boundaries, routing, and deployment gate. |
| [`local-ai/model-roster.md`](local-ai/model-roster.md) | Selected local model and inference roster, with pinned pull sources. |
| [`local-ai/tallies/`](local-ai/tallies/) | Append-only monthly model and runtime tallies; July 2026 is the anchor. |
| [`local-ai/monthly-workflow.md`](local-ai/monthly-workflow.md) | Distilled Pi/llama-swap workflow, deterministic boundary, Tally schedule, and proposal-card lifecycle. |
| [`local-ai/pi-appliance-pattern.md`](local-ai/pi-appliance-pattern.md) | Reusable single, pooled, aggregator, and typed-swarm mechanism for durable local-model appliances. |
| [`old/`](old/) | Reference-only documentation retained for later mining. |

Files under `old/` are not current operating instructions. They preserve useful
history, including assumptions that predate the NixOS fleet, the local-model
store, llama-swap routing, and the later Tally design. New work must cite the
current Nix modules and the `local-ai/` documents instead.
