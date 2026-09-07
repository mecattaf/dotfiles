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
| [`local-ai/codex-login.md`](local-ai/codex-login.md) | **Whose Codex login `/home/tom/.codex/auth.json` is** (Nayla's, R-2026-09-06-02), which Nix file seeds it, and why Tom's own login needs a `CODEX_HOME` he names. Paths only. |
| [`local-ai/claude-capacity.md`](local-ai/claude-capacity.md) | **The capacity oracle's three exit codes and its case count — 23, not the 21 a receipt claims.** Why "the two" cannot be named, and how to run the suite in and out of nix. |
| [`local-ai/seat-feeder.md`](local-ai/seat-feeder.md) | **The rewrite's three coordinator-only seat-feeder timers** — row ownership, source boundaries, the 60-second freshness contract, UNKNOWN deferrals, and the real-kernel fixture. |
| [`local-ai/tally-b-input.md`](local-ai/tally-b-input.md) | **The rewrite kernel as a flake input and one module** — why `tally-b` is `git+https://` with `flake = false`, what `modules/tally-b.nix` runs against (`tally-rewrite` state, `kernel.sock`, the meters dir, the three kernel-owned rows), and how it coexists with the live user-bus daemon as bytes. |
| [`local-ai/tally-uplink-input.md`](local-ai/tally-uplink-input.md) | **The lake as a flake input and one home module** — why `tally-lake` is consumed AS a flake (unlike `tally-b`) over `git+https://`, what `home/tally-uplink.nix` sets on the coordinator's user bus (the pinned kernel's `docs/rows.md` out of the store, the rewrite state root, the token as a path), and where a home-manager module's eval-time guard lives. |
| [`local-ai/tally-filler-timer.md`](local-ai/tally-filler-timer.md) | **The filler lane's clock** — why the "uplink's filler verb" is the register's `e1-loop.sh --all` (D-U-E1LOOP-7) and an out-of-store `%h` path, how D-B10's round-robin is carried as an *equality* against `tally-drain.timer`'s own declared period plus the lane's `/running` gate, and how a timer is proven to RUN before any switch (`launcher: shell`). |
| [`local-ai/coordinator-switch.md`](local-ai/coordinator-switch.md) | **The one coordinator switch, in P05's order** — why the gate is a FULL `nix flake check` and what it found, why a `Type=oneshot` uplink needs `RemainAfterExit` for `active` to mean anything, the two clauses that beat the card's letter (`tally-seat-feeder-cc.timer` never existed; `--failed` is not required empty, D-B98), the committed llama-swap baseline, and the unswitched worker as the negative control. |
| [`local-ai/monthly-workflow.md`](local-ai/monthly-workflow.md) | Evidence-first Git update bot, single Pi judgment, nested Tally GPU lease, and merge-only pin advancement. |
| [`local-ai/pi-appliance-pattern.md`](local-ai/pi-appliance-pattern.md) | Reusable single, pooled, aggregator, and typed-swarm mechanism for durable local-model appliances. |
| [`local-ai/dual-node-inference-lessons.md`](local-ai/dual-node-inference-lessons.md) | Preserved operational lessons from the retired dual-node ds4 cluster. History, not a deployment target. |
| [`l8-flash-reconcile.md`](l8-flash-reconcile.md) | **How `l8-flash` reached `main`, and why the order was the blocker** — the anchor rule in `home/home.nix:15`, the hand-written mirror pair and which half of its deletion is Tom's, and the U-D16 oracle. |
| [`util-01-sampler-reconcile.md`](util-01-sampler-reconcile.md) | **How the two-commit UTIL-01 sampler branch reached `main` with its semantics unchanged** — the one overlapping import line, the digests the card locks, the two `[E]` probe rows that ship RED on purpose, and the U-D17 oracle. |
| [`old/`](old/) | Archival stub: an index of the retired documentation set and how to read it back from Git history. |
| [`local-ai/wanted-packages/`](local-ai/wanted-packages/) | Findings the fleet turned up but has not acted on — one page per finding, each naming what stopped, what is measured, and what is inference. |
