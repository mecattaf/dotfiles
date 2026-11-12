# Documentation

The current documentation starts here. Every page describes code that exists;
where a page makes a claim about deployment, it names the Nix file that decides
it.

| Path | Purpose |
|---|---|
| [`local-ai/README.md`](local-ai/README.md) | The one inference server (Halogen Flash on the worker), how a Library artifact reaches a host, and the hand-run `llama-server` pattern. |
| [`local-ai/model-roster.md`](local-ai/model-roster.md) | **The 15-row catalogue** — pinned sources, which host wants which artifact, and what (if anything) serves each row. |
| [`local-ai/deployment-decisions-2026-07-29.md`](local-ai/deployment-decisions-2026-07-29.md) | Coordinator placement ledger: exact download totals, precision policy, and exclusions. |
| [`local-ai/mage.md`](local-ai/mage.md) | Selected Mage-Flow Turbo and Mage-VL snapshots, exact and deduplicated sizes, paths, and runtime boundaries. |
| [`local-ai/tallies/`](local-ai/tallies/) | Reviewed model-roster rationale; the July 29 coordinator-only tally is the accepted anchor. |
| [`local-ai/codex-login.md`](local-ai/codex-login.md) | **Whose Codex login `/home/tom/.codex/auth.json` is** (Nayla's, R-2026-09-06-02), which Nix file seeds it, and why Tom's own login needs a `CODEX_HOME` he names. Paths only. |
| [`local-ai/claude-capacity.md`](local-ai/claude-capacity.md) | **The capacity oracle's three exit codes and its case count — 23, not the 21 a receipt claims.** Why "the two" cannot be named, and how to run the suite in and out of nix. |
| [`local-ai/pi-appliance-pattern.md`](local-ai/pi-appliance-pattern.md) | Reusable single, pooled, aggregator, and typed-swarm mechanism for durable local-model appliances. |
| [`local-ai/dual-node-inference-lessons.md`](local-ai/dual-node-inference-lessons.md) | Preserved operational lessons from the retired dual-node ds4 cluster. History, not a deployment target. |
| [`l8-flash-reconcile.md`](l8-flash-reconcile.md) | **How `l8-flash` reached `main`, and why the order was the blocker** — the anchor rule in `home/home.nix:15`, the hand-written mirror pair and which half of its deletion is Tom's, and the U-D16 oracle. |
| [`util-01-sampler-reconcile.md`](util-01-sampler-reconcile.md) | **How the two-commit UTIL-01 sampler branch reached `main` with its semantics unchanged** — the one overlapping import line, the digests the card locks, the two `[E]` probe rows that ship RED on purpose, and the U-D17 oracle. |
| [`old/`](old/) | Archival stub: an index of the retired documentation set and how to read it back from Git history. |
| [`local-ai/wanted-packages/`](local-ai/wanted-packages/) | Findings the fleet turned up but has not acted on — one page per finding, each naming what stopped, what is measured, and what is inference. |
| [`scheduled.md`](scheduled.md) | **Scheduled items from the seat** — writing `<agency>/.agency/scheduled/<item>.jsonc`, the `scheduled` verbs, what the hourly heartbeat does (latest-only catch-up, the inbox record, waking the floor), where the results are, and why failure is passive. |
| [`dsh-master.md`](dsh-master.md) | **The superagent's Master profiles** — the three rendered folders, pairs (one attribute each), the `engine` key, the `dsh-master` verbs, the floor instance and its panel, and starting, checking and holding workflow runs. |
| [`runbook-conventions.md`](runbook-conventions.md) | **How a runbook suppresses a unit on NixOS** — why a plain mask fails on the read-only `/etc/systemd/system` store symlink and `mask --runtime` silently does nothing, and the intent → wrong → right table (runtime drop-in, `enable = false` + rebuild, move the data, stop the timer). |
