# Documentation

The current documentation starts here. Every page describes code that exists;
where a page makes a claim about deployment, it names the Nix file that decides
it.

| Path | Purpose |
|---|---|
| [`local-ai/README.md`](local-ai/README.md) | Current local-AI appliance boundaries, deployment mechanisms, and routing. |
| [`local-ai/model-roster.md`](local-ai/model-roster.md) | **The authoritative model split** — served, rooted, runtime-owned, and cataloged-only — with pinned sources and per-host placement. |
| [`local-ai/deployment-decisions-2026-07-29.md`](local-ai/deployment-decisions-2026-07-29.md) | Coordinator placement ledger: exact download totals, precision policy, and exclusions. |
| [`local-ai/mage.md`](local-ai/mage.md) | Selected Mage-Flow Turbo and Mage-VL snapshots, exact and deduplicated sizes, paths, and runtime boundaries. |
| [`local-ai/tallies/`](local-ai/tallies/) | Reviewed model-roster rationale; the July 29 coordinator-only tally is the accepted anchor. |
| [`local-ai/monthly-workflow.md`](local-ai/monthly-workflow.md) | Evidence-first Git update bot, single Pi judgment, nested Tally GPU lease, and merge-only pin advancement. |
| [`local-ai/pi-appliance-pattern.md`](local-ai/pi-appliance-pattern.md) | Reusable single, pooled, aggregator, and typed-swarm mechanism for durable local-model appliances. |
| [`local-ai/dual-node-inference-lessons.md`](local-ai/dual-node-inference-lessons.md) | Preserved operational lessons from the retired dual-node ds4 cluster. History, not a deployment target. |
| [`old/`](old/) | Archival stub: an index of the retired documentation set and how to read it back from Git history. |
